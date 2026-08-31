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
    /// The cached mode/fan/light values changed, whether from our own write or
    /// a read-back from the device.
    func bleManagerDidChangeSettings(_ manager: CoolerBLEManager)
    /// More than one cooler is in range, or the saved one wasn't found — the
    /// user needs to pick.
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

/// A telemetry frame from the cooler's notify characteristic.
struct CoolerTelemetry {
    /// Cold plate — the face against the Mac.
    let coldC: Int
    /// Hot side — the fin stack the fan exhausts through.
    let hotC: Int
    let ambientC: Int
    /// Fan speed in RPM, absent on shorter frames from older firmware.
    let fanRPM: Int?
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
        let peripheral: CBPeripheral
        let name: String
        let rssi: Int
        /// The model whose name hints matched this device.
        let profile: DeviceProfile
    }

    weak var delegate: CoolerBLEManagerDelegate?

    /// The model being driven. Set when discovery matches a device, and falls
    /// back to the first registered profile until then — see `DeviceProfile`.
    private(set) var profile: DeviceProfile = DeviceProfile.all[0]

    // ── Observable state ─────────────────────────────────────────────────────

    private(set) var phase: ConnectionPhase = .idle
    var isConnected: Bool { phase.isConnected }

    /// Last known device state. These mirror the device rather than command it:
    /// they're updated both by our writes (optimistically) and by read-backs.
    private(set) var mode: CoolingMode = .off
    private(set) var fanPercent: UInt8 = 0
    private(set) var lightMode: UInt8?
    private(set) var tempThreshold: UInt8?
    private(set) var deviceAutoTemp: Bool?

    /// True while we hold a peripheral with a live — or half-open — link worth
    /// tearing down at quit.
    var hasActiveLink: Bool { peripheral != nil }

    /// One-shot, fired once the peripheral has fully disconnected. Quit uses it
    /// to wait for a clean teardown before letting the process exit.
    var onDisconnect: (() -> Void)?

    // ── Internals ────────────────────────────────────────────────────────────

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var candidates: [DiscoveredDevice] = []

    private var scanSettleTimer: Timer?
    private var connectTimeoutTimer: Timer?

    /// Set while deliberately dropping a stale system-level link at launch, so
    /// `didDisconnectPeripheral` reconnects at once instead of waiting out the
    /// normal reconnect delay.
    private var clearingStaleLink = false

    /// Set when the user chose "Turn Off & Disconnect". Suppresses the
    /// automatic reconnect so the link stays down until they ask for it back.
    private var userRequestedDisconnect = false

    private var characteristics: [CBUUID: CBCharacteristic] = [:]

    override init() {
        super.init()
        // A nil queue delivers delegate callbacks on the main queue, which is
        // what every consumer here expects.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // ── Connection lifecycle ─────────────────────────────────────────────────

    /// Reconnects to the saved cooler, or scans if none is known.
    ///
    /// Safe to call repeatedly; it cancels any standing user-requested
    /// disconnect but will not disturb an attempt already in flight.
    func startScanning() {
        userRequestedDisconnect = false

        guard central.state == .poweredOn else {
            EventLogger.record("BLE — cannot scan, adapter state \(central.state.rawValue)")
            return
        }

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

            // Re-match the profile from the saved name, in case a different
            // model was used last time. Falls back to the current profile when
            // macOS has no name cached.
            if let name = known.name, let matched = DeviceProfile.matching(deviceName: name) {
                profile = matched
            }
            EventLogger.record("BLE — reconnecting to known peripheral")
            beginConnect(to: known)
            return
        }

        // The cooler omits its service UUID from the scan record, so filtering
        // by service here would never match it. Scan broadly and filter by name
        // in didDiscover instead.
        EventLogger.record("BLE — no cached peripheral, scanning")
        setPhase(.scanning)
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    /// The previously-connected peripheral, if one is saved and macOS still
    /// knows it. Returns `nil` on a cold cache, which sends us down the scan
    /// path instead.
    private func knownPeripheral() -> CBPeripheral? {
        guard let saved = UserDefaults.standard.string(forKey: Config.Key.preferredDevice),
              let uuid = UUID(uuidString: saved) else { return nil }
        return central.retrievePeripherals(withIdentifiers: [uuid]).first
    }

    /// Connects to a device the user picked in the device chooser.
    func connect(to device: DiscoveredDevice) {
        central.stopScan()
        scanSettleTimer?.invalidate()
        scanSettleTimer = nil
        candidates = []
        profile = device.profile
        beginConnect(to: device.peripheral)
    }

    /// The single entry point for initiating a connection. Arms a watchdog
    /// because CoreBluetooth's `connect()` never times out on its own.
    private func beginConnect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        setPhase(.connecting(name: peripheral.name))
        central.connect(peripheral, options: nil)

        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(
            withTimeInterval: Config.BLE.connectTimeout, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            EventLogger.record("BLE — connect timed out, retrying")
            self.central.cancelPeripheralConnection(peripheral)
            self.setPhase(.reconnecting)
            self.scheduleReconnect()
        }
    }

    /// Drops the link but leaves automatic reconnection enabled.
    func disconnect() {
        cancelTimers()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    /// User-initiated disconnect that stays down, freeing the cooler's single
    /// connection slot (so, say, the phone app can pair) until the user
    /// explicitly reconnects.
    func disconnectAndStop() {
        userRequestedDisconnect = true
        cancelTimers()
        central.stopScan()

        guard let peripheral else {
            // Nothing connected — settle straight into idle.
            userRequestedDisconnect = false
            setPhase(.idle)
            delegate?.bleManager(self, didChangeConnected: false)
            return
        }
        EventLogger.record("BLE — user requested disconnect")
        central.cancelPeripheralConnection(peripheral)
    }

    /// Forgets the current device and clears discovery state, for "Change Device".
    func resetForRescan() {
        cancelTimers()
        candidates = []
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
    }

    private func cancelTimers() {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        scanSettleTimer?.invalidate()
        scanSettleTimer = nil
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.reconnectDelay) {
            [weak self] in
            self?.startScanning()
        }
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

    private func write(_ bytes: [UInt8], to uuid: CBUUID) {
        guard let peripheral, let characteristic = characteristics[uuid] else { return }
        peripheral.writeValue(Data(bytes), for: characteristic, type: .withResponse)
    }

    /// Sets the TEC power level.
    ///
    /// Prefer `apply(mode:fanPercent:)` when changing both mode and fan — the
    /// device needs them separated in time.
    func setMode(_ mode: CoolingMode) {
        self.mode = mode
        write([mode.rawValue], to: profile.coolingModeUUID)
    }

    func setFanPercent(_ percent: UInt8) {
        let clamped = min(percent, 100)
        fanPercent = clamped
        write([clamped], to: profile.fanSpeedUUID)
    }

    /// Applies a mode and fan speed together, in the order the cooler expects.
    ///
    /// The fan write is deferred by `Config.BLE.fanWriteDelay`: sent in the same
    /// connection interval as a mode change the device silently drops it, which
    /// is what used to leave the fan stuck at its previous speed after a mode
    /// switch. Every caller changing both values should use this rather than
    /// re-deriving the delay — that duplication was the original bug's habitat.
    ///
    /// Turning off forces the fan to 0 regardless of the requested percentage.
    func apply(mode: CoolingMode, fanPercent: UInt8) {
        setMode(mode)
        let target = mode.isOn ? fanPercent : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.fanWriteDelay) {
            [weak self] in
            self?.setFanPercent(target)
        }
    }

    /// Re-asserts the cached mode and fan speed, healing any dropped write.
    func reassertCurrentSettings() {
        apply(mode: mode, fanPercent: fanPercent)
    }

    /// Writes the light characteristic as `[effect, R, G, B]`.
    ///
    /// The colour bytes are honoured by the monochrome-breath (3), stroke (4)
    /// and static effects and ignored by the rest. `effect` is deliberately
    /// unclamped: the probe scripts in `tools/probe/` write bytes above the
    /// range the UI exposes, to map undocumented effects.
    func setLight(effect: UInt8, color: RGB = .black) {
        write([effect] + color.bytes, to: profile.lightModeUUID)
    }

    /// The device's own auto-engage threshold, in °C. Independent of this app's
    /// autopilot; the UI leaves it alone, but the CLI can probe it.
    func setTempThreshold(_ celsius: UInt8) {
        write([min(celsius, 60)], to: profile.tempThreshUUID)
    }

    /// Toggles the device's built-in temperature automation.
    func setDeviceAutoTemp(_ enabled: Bool) {
        write([enabled ? 1 : 0], to: profile.autoTempUUID)
    }
}

// ── Central manager delegate ─────────────────────────────────────────────────

extension CoolerBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            EventLogger.record("BLE — adapter powered on")
            startScanning()
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
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? ""
        guard let matched = DeviceProfile.matching(deviceName: name) else { return }
        guard !candidates.contains(where: { $0.peripheral.identifier == peripheral.identifier })
        else { return }

        candidates.append(DiscoveredDevice(
            peripheral: peripheral,
            name: name.isEmpty ? peripheral.identifier.uuidString : name,
            rssi: RSSI.intValue,
            profile: matched))
        EventLogger.record("BLE — found \"\(name)\" at \(RSSI) dBm")
        setPhase(.connecting(name: name.isEmpty ? nil : name))

        // Restart the settle window on each hit so nearby coolers appearing a
        // moment later still make it into the picker.
        scanSettleTimer?.invalidate()
        scanSettleTimer = Timer.scheduledTimer(
            withTimeInterval: Config.BLE.scanSettleWindow, repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            central.stopScan()
            self.delegate?.bleManager(self, needsDeviceSelection: self.candidates)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        UserDefaults.standard.set(peripheral.identifier.uuidString,
                                  forKey: Config.Key.preferredDevice)
        EventLogger.record("BLE — connected to \(peripheral.name ?? "cooler")")
        setPhase(.discoveringServices)
        peripheral.discoverServices([profile.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        EventLogger.record("BLE — connect failed: \(error?.localizedDescription ?? "unknown")")
        setPhase(.reconnecting)
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
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

        // User asked to stay disconnected — free the slot and idle.
        if userRequestedDisconnect {
            userRequestedDisconnect = false
            self.peripheral = nil
            setPhase(.idle)
            return
        }

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
        guard let service = peripheral.services?.first(where: { $0.uuid == profile.serviceUUID })
        else { return }
        setPhase(.discoveringCharacteristics)
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let discovered = service.characteristics else { return }

        // Match on CBUUID rather than uuidString: CoreBluetooth shortens 128-bit
        // UUIDs in the Bluetooth base range to their 16-bit form ("1011"), so
        // comparing against full-length UUID strings never matches.
        let notifying = profile.notifyingUUIDs
        let readable = profile.readableUUIDs

        for characteristic in discovered {
            let uuid = characteristic.uuid
            guard notifying.contains(uuid) || readable.contains(uuid) else { continue }
            characteristics[uuid] = characteristic

            if notifying.contains(uuid) {
                peripheral.setNotifyValue(true, for: characteristic)
            } else {
                peripheral.readValue(for: characteristic)
            }
        }
        setPhase(.ready)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }

        switch characteristic.uuid {
        case profile.coolingModeUUID:
            mode = CoolingMode(rawValue: data[0])
            delegate?.bleManagerDidChangeSettings(self)

        case profile.fanSpeedUUID:
            fanPercent = data[0]
            delegate?.bleManagerDidChangeSettings(self)

        case profile.lightModeUUID:
            lightMode = data[0]
            delegate?.bleManagerDidChangeSettings(self)

        case profile.tempThreshUUID:
            tempThreshold = data[0]
            delegate?.bleManagerDidChangeSettings(self)

        case profile.autoTempUUID:
            deviceAutoTemp = data[0] != 0
            delegate?.bleManagerDidChangeSettings(self)

        case profile.hallUUID:
            delegate?.bleManager(self, didChangeMountAttached: profile.decodeMountAttached(data))

        case profile.telemetryUUID:
            guard let telemetry = profile.decodeTelemetry(data) else { return }
            delegate?.bleManager(self, didReceive: telemetry)

        default:
            break
        }
    }
}
