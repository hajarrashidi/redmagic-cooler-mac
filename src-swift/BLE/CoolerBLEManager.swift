import Foundation
import CoreBluetooth

/// Callbacks from `CoolerBLEManager`. All are delivered on the main queue.
///
/// Every method has a default no-op implementation, so a conformer only
/// implements the events it cares about.
protocol CoolerBLEManagerDelegate: AnyObject {
    func bleManager(_ manager: CoolerBLEManager, didChangePhase phase: ConnectionPhase)
    func bleManager(_ manager: CoolerBLEManager, didChangeConnected isConnected: Bool)
    func bleManager(_ manager: CoolerBLEManager, didReceive telemetry: CoolerTelemetry)
    func bleManager(_ manager: CoolerBLEManager, didChangeMountAttached attached: Bool)
    /// The cached mode/fan values changed, whether from our own write or a
    /// read-back from the device.
    func bleManagerDidChangeSettings(_ manager: CoolerBLEManager)
    /// Supported coolers were found and the user needs to pick one. Selection
    /// is always explicit, even when discovery finds only one device.
    func bleManager(_ manager: CoolerBLEManager,
                    needsDeviceSelection devices: [CoolerBLEManager.DiscoveredDevice])
}

extension CoolerBLEManagerDelegate {
    func bleManager(_ manager: CoolerBLEManager, didChangePhase phase: ConnectionPhase) {}
    func bleManager(_ manager: CoolerBLEManager, didChangeConnected isConnected: Bool) {}
    func bleManager(_ manager: CoolerBLEManager, didReceive telemetry: CoolerTelemetry) {}
    func bleManager(_ manager: CoolerBLEManager, didChangeMountAttached attached: Bool) {}
    func bleManagerDidChangeSettings(_ manager: CoolerBLEManager) {}
    func bleManager(_ manager: CoolerBLEManager,
                    needsDeviceSelection devices: [CoolerBLEManager.DiscoveredDevice]) {}
}

/// Owns the Bluetooth link to the cooler: discovery, connection lifecycle,
/// characteristic writes, and telemetry decoding.
///
/// ### Why this is more than a thin CoreBluetooth wrapper
///
/// The cooler accepts exactly **one** connection at a time and does not drop a
/// half-open link promptly — it holds the slot until its supervision timeout.
/// A previous app instance that exited without disconnecting therefore locks
/// out the next launch entirely. Three mechanisms handle that:
///
///  * On launch, a peripheral macOS still reports as connected is explicitly
///    cancelled first, then reconnected (`clearingStaleLink`).
///  * `connect()` has no timeout of its own, so `beginConnect` arms a watchdog
///    and retries rather than hanging in `.connecting` forever.
///  * Quit tears the link down deliberately and waits for confirmation, so the
///    slot is free before the process exits.
final class CoolerBLEManager: NSObject {

    struct DiscoveredDevice {

        /// How well the app knows a discovered device.
        ///
        /// Only `.supported` is connectable. The other two exist so the picker
        /// can *show* a cooler it can't drive: silently dropping it, as the app
        /// used to, left the owner of a newer model staring at "no supported
        /// coolers found" with no way to tell whether the app had even seen it.
        enum Support {
            /// A registered profile matched by name. Drivable.
            case supported(DeviceProfile)
            /// Recognisably a vendor cooler, but no profile matches.
            case unsupported
            /// Any other named device. Listed too, so a cooler advertising an
            /// unexpected name is still findable — that name is step one of
            /// the porting guide.
            case other
        }

        let peripheral: CBPeripheral
        let name: String
        let rssi: Int
        let support: Support

        /// The model to drive this device with, or `nil` if the app has none.
        var profile: DeviceProfile? {
            guard case .supported(let profile) = support else { return nil }
            return profile
        }

        var isSupported: Bool { profile != nil }
    }

    weak var delegate: CoolerBLEManagerDelegate?

    /// The model being driven. It remains unset until an explicit device choice
    /// is made or safely restored; registry order never implies selection.
    private(set) var profile: DeviceProfile?

    // ── Observable state ─────────────────────────────────────────────────────

    private(set) var phase: ConnectionPhase = .idle
    var isConnected: Bool { phase.isConnected }

    /// Last known device state. These mirror the device rather than command it:
    /// they're updated both by our writes (optimistically) and by read-backs.
    private(set) var mode: CoolingMode = .off
    private(set) var fanPercent: UInt8 = 0

    /// True while we hold a peripheral with a live — or half-open — link worth
    /// tearing down at quit.
    var hasActiveLink: Bool { peripheral != nil }

    /// A cooler has been chosen at some point, so "Connect" has something to
    /// aim at. Deliberately reads the saved UUID rather than
    /// `knownPeripheral()`: whether macOS still has the peripheral cached
    /// decides how `startScanning` reconnects, not whether the menu should
    /// offer to. With nothing saved the menu leads with the picker instead.
    private var preferredDeviceUUIDString: String? {
        if let saved = UserDefaults.standard.string(forKey: Config.Key.preferredDevice) {
            return saved
        }
        if let legacy = UserDefaults(suiteName: "com.redmagic.cooler")?.string(forKey: Config.Key.preferredDevice) {
            UserDefaults.standard.set(legacy, forKey: Config.Key.preferredDevice)
            return legacy
        }
        return nil
    }

    var hasKnownDevice: Bool {
        preferredDeviceUUIDString != nil
    }

    /// One-shot, fired once the peripheral has fully disconnected. Quit uses it
    /// to wait for a clean teardown before letting the process exit.
    var onDisconnect: (() -> Void)?

    // ── Internals ────────────────────────────────────────────────────────────

    /// Nil until the user first asks for a connection — see `activateCentral`.
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var candidates: [DiscoveredDevice] = []

    private var scanSettleTimer: Timer?
    private var connectTimeoutTimer: Timer?
    /// The one scheduled reconnect, kept so it can be cancelled — by a
    /// rescan, or by a newer schedule. A plain `asyncAfter` here used to fire
    /// regardless, starting a second attempt racing the first.
    private var pendingReconnect: DispatchWorkItem?

    /// Set while deliberately dropping a stale system-level link at launch, so
    /// `didDisconnectPeripheral` reconnects at once instead of waiting out the
    /// normal reconnect delay.
    private var clearingStaleLink = false

    /// True only after the user has initiated a connection in this app session.
    /// Before that, the menu stays idle and leads with its Connect action.
    private var connectionRequested = false

    /// Set while "Change Device" is dropping the current link. Discovery must
    /// wait for that disconnect, and its callback must not schedule a reconnect
    /// to the device the user is replacing.
    private var rescanAfterDisconnect = false

    /// The active hardware driver bound strictly to the selected profile.
    private var activeDriver: CoolerDriver?

    private var characteristics: [CBUUID: CBCharacteristic] = [:]

    // ── Permission ───────────────────────────────────────────────────────────

    /// What the app is allowed to do with Bluetooth, readable without owning a
    /// central manager — which matters, because creating one is what triggers
    /// the prompt.
    enum Permission {
        case granted
        /// Never asked. The app has something to *offer* here rather than
        /// something to report, so the menu shows a button instead of an error.
        case notAsked
        /// Asked and refused, or blocked by policy. Only System Settings can
        /// undo it.
        case denied
    }

    var permission: Permission {
        switch CBManager.authorization {
        case .allowedAlways:  return .granted
        case .notDetermined:  return .notAsked
        default:              return .denied
        }
    }

    /// Creates the central manager, and with it triggers macOS's Bluetooth
    /// permission prompt.
    ///
    /// Deliberately not done at launch. Opening a menu-bar app is not consent
    /// to a permission dialog, and one that fires before the app has shown what
    /// it is for is the version that gets denied — after which only System
    /// Settings can undo it. So the manager comes up on the first press of
    /// Connect, Scan or Allow Bluetooth Access, and the menu explains itself
    /// first.
    private func activateCentral() -> CBCentralManager {
        if let central { return central }
        EventLogger.record("BLE — activating adapter (may prompt for permission)")
        let created = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        EventLogger.record("BLE — created central, delegate set to: \(type(of: created.delegate!))")
        central = created
        return created
    }

    /// Brings the adapter up for the sole purpose of asking. The menu's "Allow
    /// Bluetooth Access" button lands here; whichever way the user answers,
    /// `centralManagerDidUpdateState` reports it and the menu re-draws.
    func requestPermission() {
        _ = activateCentral()
    }

    // ── Connection lifecycle ─────────────────────────────────────────────────

    /// Reconnects to a previously selected cooler, or scans so the user can
    /// choose one when this manager has no selection yet.
    ///
    /// Safe to call repeatedly; it will not disturb an attempt already in
    /// flight.
    func startScanning() {
        connectionRequested = true
        // This call supersedes any reconnect still queued; letting it fire too
        // would start a second attempt racing this one.
        pendingReconnect?.cancel()
        pendingReconnect = nil

        // First call of the session brings the adapter up. Its state arrives
        // asynchronously, so this returns here and `centralManagerDidUpdateState`
        // calls back in — `connectionRequested` is what tells it to.
        let central = activateCentral()
        guard central.state == .poweredOn else {
            EventLogger.record("BLE — cannot scan, adapter state \(central.state.rawValue)")
            return
        }
        guard !rescanAfterDisconnect else { return }

        if let known = knownPeripheral() {
            // macOS still shows it connected: that's a stale link from an
            // aborted session. Drop it so the cooler frees its single slot,
            // then reconnect — driven by didDisconnectPeripheral, with a
            // fallback timer in case that callback never arrives.
            if known.state == .connected || known.state == .connecting {
                EventLogger.record("BLE — clearing stale link before reconnecting")
                peripheral = known
                known.delegate = self
                clearingStaleLink = true
                setPhase(.reconnecting)
                central.cancelPeripheralConnection(known)

                DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.staleLinkClearTimeout) {
                    [weak self] in
                    guard let self, self.clearingStaleLink else { return }
                    self.clearingStaleLink = false
                    self.startScanning()
                }
                return
            }

            // A saved UUID records an earlier explicit choice. Restore its
            // profile only when the cached name or saved profile ID positively matches
            // a supported model; a missing or unknown name goes through discovery instead
            // of falling back to the first registry entry.
            if profile == nil {
                if let savedId = UserDefaults.standard.string(forKey: Config.Key.preferredDeviceProfileId),
                   let matched = DeviceProfile.all.first(where: { $0.id == savedId }) {
                    profile = matched
                } else if let name = known.name,
                          let matched = DeviceProfile.matching(deviceName: name) {
                    profile = matched
                    UserDefaults.standard.set(matched.id, forKey: Config.Key.preferredDeviceProfileId)
                }
            }
            if let profile {
                activeDriver = profile.makeDriver()
                EventLogger.record("BLE — reconnecting to selected peripheral (\(profile.modelName))")
                beginConnect(to: known)
                return
            }
        }

        // The cooler omits its service UUID from the scan record, so filtering
        // by service here would never match it. Scan broadly and filter by name
        // in didDiscover instead.
        //
        // Results from any earlier scan are dropped first: a device that has
        // since left range must not linger in the picker, and a stale RSSI
        // would misreport the signal of one that stayed.
        candidates = []
        EventLogger.record("BLE — scanning for device selection")
        setPhase(.scanning)
        central.scanForPeripherals(withServices: nil, options: nil)
        // Armed up front, not just on a hit: a scan that finds nothing must
        // still end in a picker that says so, rather than spinning forever.
        armScanSettleTimer()
    }

    /// Ends the scan after a quiet period and hands the results to the picker.
    private func armScanSettleTimer() {
        scanSettleTimer?.invalidate()
        scanSettleTimer = Timer.scheduledTimer(
            withTimeInterval: Config.BLE.scanSettleWindow, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.central?.stopScan()
            self.setPhase(.idle)
            self.delegate?.bleManager(self, needsDeviceSelection: self.candidates)
        }
    }

    /// The previously-connected peripheral, if one is saved and macOS still
    /// knows it. Returns `nil` on a cold cache, which sends us down the scan
    /// path instead.
    private func knownPeripheral() -> CBPeripheral? {
        guard let saved = preferredDeviceUUIDString,
              let uuid = UUID(uuidString: saved) else { return nil }
        return central?.retrievePeripherals(withIdentifiers: [uuid]).first
    }

    /// Connects to a device the user picked in the device chooser.
    ///
    /// Unsupported devices are listed in that chooser but refused here: without
    /// a profile the app knows neither which characteristics to drive nor what
    /// its telemetry means, so connecting could only write guessed bytes to
    /// unfamiliar hardware.
    func connect(to device: DiscoveredDevice) {
        guard let chosen = device.profile else {
            EventLogger.record("BLE — refusing unsupported device \"\(device.name)\"")
            return
        }
        central?.stopScan()
        scanSettleTimer?.invalidate()
        scanSettleTimer = nil
        candidates = []
        profile = chosen
        UserDefaults.standard.set(chosen.id, forKey: Config.Key.preferredDeviceProfileId)
        activeDriver = chosen.makeDriver()
        beginConnect(to: device.peripheral)
    }

    /// The single entry point for initiating a connection. Arms a watchdog
    /// because CoreBluetooth's `connect()` never times out on its own.
    ///
    /// The watchdog runs until the link is `.ready`, not merely until
    /// `didConnect`: service and characteristic discovery can stall just as
    /// silently as the connect itself, and a link stuck in "Discovering
    /// services…" is every bit as unusable as one stuck in `.connecting`.
    private func beginConnect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        setPhase(.connecting(name: peripheral.name))
        central?.connect(peripheral, options: nil)

        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: Config.BLE.connectTimeout, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            EventLogger.record("BLE — connect timed out, retrying")
            self.central?.cancelPeripheralConnection(peripheral)
            self.setPhase(.reconnecting)
            self.scheduleReconnect()
        }
    }

    /// Drops the link but leaves automatic reconnection enabled.
    func disconnect() {
        cancelTimers()
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
    }

    /// Forgets the current device and clears discovery state, for "Change Device".
    func resetForRescan() {
        cancelTimers()
        central?.stopScan()
        candidates = []
        profile = nil
        activeDriver?.disconnect()
        activeDriver = nil
        UserDefaults.standard.removeObject(forKey: Config.Key.preferredDeviceProfileId)
        characteristics.removeAll()

        if let peripheral, peripheral.state != .disconnected {
            rescanAfterDisconnect = true
            setPhase(.scanning)
            central?.cancelPeripheralConnection(peripheral)
        } else {
            self.peripheral = nil
            setPhase(.idle)
        }
    }

    private func cancelTimers() {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        scanSettleTimer?.invalidate()
        scanSettleTimer = nil
        pendingReconnect?.cancel()
        pendingReconnect = nil
    }

    /// Resumes a "Change Device" scan, if this teardown was the one it asked
    /// for.
    ///
    /// Both disconnect callbacks have to ask: cancelling an *in-flight*
    /// connection surfaces as `didFailToConnect`, cancelling a live one as
    /// `didDisconnectPeripheral`, and the user's rescan must survive either.
    ///
    /// - Returns: `true` when it consumed the event, so the caller stops rather
    ///   than reconnecting to the cooler being replaced.
    private func resumeRescanIfPending() -> Bool {
        guard rescanAfterDisconnect else { return false }
        rescanAfterDisconnect = false
        peripheral = nil
        startScanning()
        return true
    }

    /// Queues one reconnect attempt. Coalescing: a newer schedule replaces a
    /// pending one, so the watchdog and a late disconnect callback reporting
    /// the same failure can't stack two attempts that then race each other.
    private func scheduleReconnect() {
        pendingReconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReconnect = nil
            self.startScanning()
        }
        pendingReconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.reconnectDelay,
                                      execute: work)
    }

    private func setPhase(_ newPhase: ConnectionPhase) {
        guard phase != newPhase else { return }
        let wasConnected = phase.isConnected
        phase = newPhase

        if newPhase.isConnected != wasConnected {
            delegate?.bleManager(self, didChangeConnected: newPhase.isConnected)
        }
        delegate?.bleManager(self, didChangePhase: newPhase)
    }

    // ── Writes ───────────────────────────────────────────────────────────────

    /// Sets the TEC power level.
    func setMode(_ mode: CoolingMode) {
        apply(mode: mode, fanPercent: fanPercent)
    }

    func setFanPercent(_ percent: UInt8) {
        apply(mode: mode, fanPercent: percent)
    }

    /// Applies a mode and fan speed together via the hardware's active driver.
    func apply(mode: CoolingMode, fanPercent: UInt8) {
        self.mode = mode
        let target = mode.isOn ? min(fanPercent, 100) : 0
        self.fanPercent = target
        if let activeDriver, let peripheral {
            activeDriver.apply(mode: mode, fanPercent: target, peripheral: peripheral)
        }
    }

    /// Re-asserts the cached mode and fan speed, healing any dropped write.
    func reassertCurrentSettings() {
        apply(mode: mode, fanPercent: fanPercent)
    }

    /// Writes the light characteristic using the active hardware driver.
    func setLight(effect: UInt8, color: RGB = .black) {
        if let activeDriver, let peripheral {
            activeDriver.setLight(effect: effect, color: color, peripheral: peripheral)
        }
    }

}

// ── Central manager delegate ─────────────────────────────────────────────────

extension CoolerBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        EventLogger.record("BLE — centralManagerDidUpdateState: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            EventLogger.record("BLE — adapter powered on")
            if connectionRequested {
                startScanning()
            } else {
                setPhase(.idle)
            }
        case .poweredOff:
            EventLogger.record("BLE — adapter powered off")
            setPhase(.bluetoothOff)
        case .unauthorized:
            EventLogger.record("BLE — unauthorized; grant Bluetooth access in "
                             + "System Settings → Privacy & Security → Bluetooth")
            setPhase(.bluetoothUnauthorized)
        case .unsupported:
            EventLogger.record("BLE — unsupported on this hardware")
            setPhase(.bluetoothOff)
        default:
            setPhase(.idle)
        }

        // Announced even when the phase label didn't move. Answering the
        // permission prompt takes the adapter from unknown to powered-on —
        // `.idle` both sides — and that is exactly the moment the menu has to
        // stop offering "Allow Bluetooth Access". Nothing else would tell it:
        // the master tick doesn't run while a menu is tracking the mouse.
        delegate?.bleManager(self, didChangePhase: phase)
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        // An unnamed device can be neither identified nor usefully reported.
        guard !name.isEmpty else { return }
        guard !candidates.contains(where: { $0.peripheral.identifier == peripheral.identifier })
        else { return }

        let support: DiscoveredDevice.Support
        if let matched = DeviceProfile.matching(deviceName: name, advertisementData: advertisementData) {
            support = .supported(matched)
        } else if DeviceProfile.looksLikeVendorDevice(deviceName: name) {
            support = .unsupported
        } else {
            support = .other
        }

        candidates.append(DiscoveredDevice(peripheral: peripheral,
                                           name: name,
                                           rssi: RSSI.intValue,
                                           support: support))

        switch support {
        case .supported:
            EventLogger.record("BLE — found supported \"\(name)\" at \(RSSI) dBm")
        case .unsupported:
            EventLogger.record("BLE — found unsupported vendor device \"\(name)\" at \(RSSI) dBm")
        case .other:
            // Logging every BLE device in radio range would drown the timeline.
            return
        }

        // Restart the settle window on each *cooler* hit so one appearing a
        // moment later still makes it into the picker. Deliberately not for
        // unrelated devices: in a busy room they arrive continuously, and
        // extending the deadline for each would keep the picker from ever
        // appearing.
        armScanSettleTimer()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // The watchdog stays armed: the link isn't usable until characteristic
        // discovery finishes, and discovery can stall as silently as connect.
        guard let profile else {
            EventLogger.record("BLE — connected without a selected device profile; disconnecting")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        if activeDriver == nil {
            activeDriver = profile.makeDriver()
        }
        UserDefaults.standard.set(peripheral.identifier.uuidString,
                                  forKey: Config.Key.preferredDevice)
        UserDefaults.standard.set(profile.id,
                                  forKey: Config.Key.preferredDeviceProfileId)
        EventLogger.record("BLE — connected to \(peripheral.name ?? profile.modelName)")
        setPhase(.discoveringServices)
        activeDriver?.didConnect(peripheral: peripheral)
        peripheral.discoverServices([profile.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        activeDriver?.disconnect()
        activeDriver = nil
        EventLogger.record("BLE — connect failed: \(error?.localizedDescription ?? "unknown")")

        // Move on to discovery rather than retrying the device being replaced.
        if resumeRescanIfPending() { return }

        setPhase(.reconnecting)
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        activeDriver?.disconnect()
        activeDriver = nil
        characteristics.removeAll()
        EventLogger.record("BLE — disconnected"
                         + (error.map { ": \($0.localizedDescription)" } ?? " cleanly"))

        // Quit-time teardown: hand control back to the waiter and stop.
        if let completion = onDisconnect {
            onDisconnect = nil
            self.peripheral = nil
            setPhase(.idle)
            completion()
            return
        }

        // "Change Device" deliberately dropped this link. The old cooler's
        // single connection slot is free now, so the fresh scan can start.
        if resumeRescanIfPending() { return }

        setPhase(.reconnecting)

        // We just cleared a stale link at launch; the slot is free now, so skip
        // the reconnect delay.
        if clearingStaleLink {
            clearingStaleLink = false
            startScanning()
            return
        }
        scheduleReconnect()
    }
}

// ── Peripheral delegate ──────────────────────────────────────────────────────

extension CoolerBLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let profile else { return }
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID })
        else { return }
        setPhase(.discoveringCharacteristics)
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let activeDriver, let discovered = service.characteristics else { return }

        let notifying = activeDriver.notifyingUUIDs
        let writable = activeDriver.writableUUIDs

        var mapped: [CBUUID: CBCharacteristic] = [:]
        for characteristic in discovered {
            let uuid = characteristic.uuid
            let uuidStr = uuid.uuidString.lowercased()
            let isNotifying = notifying.contains(uuid)
                || uuidStr.contains("1015") || uuidStr.contains("1016")
                || uuidStr.contains("a002") || uuidStr.contains("ffe4")
            let isWritable = writable.contains(uuid)
                || uuidStr.contains("1011") || uuidStr.contains("1012") || uuidStr.contains("1013")
                || uuidStr.contains("a001") || uuidStr.contains("ffe1")

            guard isNotifying || isWritable else { continue }
            mapped[uuid] = characteristic

            if isNotifying {
                EventLogger.record("BLE — subscribing to notification on \(uuid.uuidString)")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        activeDriver.didDiscoverCharacteristics(characteristics: mapped, peripheral: peripheral)

        // Fully linked — the watchdog armed in beginConnect can stand down.
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        setPhase(.ready)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            EventLogger.record("BLE — write error on \(characteristic.uuid.uuidString): \(error.localizedDescription)")
        } else {
            EventLogger.record("BLE — write confirmed on \(characteristic.uuid.uuidString)")
            if characteristic.uuid.uuidString.lowercased().contains("1012") {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let activeDriver else { return }
        let update = activeDriver.handleCharacteristicUpdate(characteristic: characteristic, peripheral: peripheral)

        switch update {
        case .mode(let newMode):
            self.mode = newMode
            delegate?.bleManagerDidChangeSettings(self)

        case .fan(let newFan):
            self.fanPercent = newFan
            delegate?.bleManagerDidChangeSettings(self)

        case .mountAttached(let attached):
            delegate?.bleManager(self, didChangeMountAttached: attached)

        case .telemetry(let telemetry):
            delegate?.bleManager(self, didReceive: telemetry)

        case .none:
            break
        }
    }
}
