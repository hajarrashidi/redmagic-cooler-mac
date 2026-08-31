import AppKit

/// Application lifecycle and the master control loop.
///
/// Responsibilities are split across extensions in the neighbouring files:
///
/// | File                       | Concern                                  |
/// |----------------------------|------------------------------------------|
/// | `AppDelegate.swift`        | lifecycle, state, the 1 Hz tick          |
/// | `AppDelegate+Menu.swift`   | building the menu                        |
/// | `AppDelegate+Actions.swift`| responding to user input                 |
/// | `AppDelegate+Refresh.swift`| pushing state into the UI                |
/// | `AppDelegate+BLE.swift`    | device callbacks and CLI commands        |
///
/// The app is `.accessory`: no Dock icon, no main window, driven entirely from
/// the menu-bar item.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // ── Collaborators ────────────────────────────────────────────────────────

    var ble: CoolerBLEManager!
    var autopilot: AutopilotPolicy!
    var led: LedController!

    // ── Menu ─────────────────────────────────────────────────────────────────

    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var devicePicker: DevicePickerWindowController?

    /// Custom rows. Held so `refresh()` can update and show/hide them without
    /// rebuilding the menu, which would close it under the user's cursor.
    var statusCard: StatusCardView!
    var modeSwitch: ModeSwitchView!
    var autoOptions: AutoOptionsView!
    var coolingSlider: CoolingSliderView!
    var effectPicker: LedEffectPickerView!
    var breathToggle: BreathStyleToggleView!
    var colorPicker: HueSpectrumPickerView!

    /// The menu items wrapping those rows, plus the plain items whose
    /// visibility depends on state.
    var rows: MenuRows!

    // ── State ────────────────────────────────────────────────────────────────

    /// Which control loop the user has selected. Distinct from the device's
    /// own mode: in `.auto` the autopilot writes the device mode, in `.manual`
    /// the slider does.
    var appMode: AppMode = .auto

    /// Latest thermal sample, refreshed each tick.
    var thermal = ThermalMonitor.Reading(thermalState: .nominal, dieTemperatureC: nil)
    /// Latest telemetry frame from the cooler, cleared when the link drops.
    var telemetry: CoolerTelemetry?
    /// Whether the magnetic mount is seated.
    var mountAttached: Bool?

    /// True briefly after a user-initiated change, while writes are in flight.
    /// Controls are disabled meanwhile so a second command can't race the first,
    /// and the slider is left alone so it doesn't snap away from where the user
    /// dropped it before the device has caught up.
    var isSwitching = false
    private var switchingTimer: Timer?

    /// Set when the user explicitly asks to connect, so the cooler can be
    /// commanded off once the link is up — a known-safe starting state.
    var turnOffOnConnect = false

    private var tickTimer: Timer?
    private var tickCount = 0

    /// Guards against `applicationShouldTerminate` running its teardown twice.
    private var isTerminating = false
    /// Retained for the lifetime of the app; a signal source stops firing when
    /// it deallocates.
    private var sigtermSource: DispatchSourceSignal?

    // ── Launch ───────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Hand the Bluetooth link over from any previous instance before doing
        // anything else — the cooler allows only one connection, so until the
        // old process exits this one cannot connect at all.
        SingleInstance.terminateOthersAndWait()

        IPCBridge.writePIDFile()
        installSignalHandler()
        loadSettings()

        ble = CoolerBLEManager()
        ble.delegate = self
        led = LedController(ble: ble)

        buildStatusItem()
        buildMenu()

        tickTimer = Timer.scheduledTimer(withTimeInterval: Config.Timing.poll,
                                         repeats: true) { [weak self] _ in
            self?.tick()
        }

        EventLogger.record("app start — mode=\(appMode.rawValue) profile=\(autopilot.profile.rawValue)")

        // The friendly Mac name needs system_profiler, which is far too slow to
        // block launch on; refresh the menu once it lands.
        SystemInfo.resolveModelName { [weak self] _ in self?.refresh() }

        writeStatusSnapshot()
        ble.startScanning()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        appMode = AppMode(persisted: defaults.string(forKey: Config.Key.appMode))

        let profile = AutoProfile(persisted: defaults.string(forKey: Config.Key.autoProfile))
        let engageC = defaults.object(forKey: Config.Key.customEngageC) as? Double
            ?? Config.Autopilot.customEngageDefaultC
        autopilot = AutopilotPolicy(profile: profile, customEngageC: engageC)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = RedMagicLogo.image(size: 16, template: true)
        button.imagePosition = .imageOnly
        button.contentTintColor = .tertiaryLabelColor
    }

    /// Routes SIGTERM — sent by a newer instance asking us to quit — through
    /// Cocoa's normal termination path, so `applicationShouldTerminate` runs and
    /// the Bluetooth link is released. The default handler would kill the
    /// process outright and leak the cooler's connection slot.
    ///
    /// A `DispatchSourceSignal` is used rather than a `signal()` handler because
    /// its callback runs on a normal queue, where calling into Cocoa is legal;
    /// almost nothing is safe to call from inside a real signal handler.
    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source
    }

    // ── Tick ─────────────────────────────────────────────────────────────────

    /// The master loop, once a second: sample temperature, run the autopilot,
    /// re-assert device state, refresh the UI, publish status.
    private func tick() {
        tickCount += 1

        handlePendingCommand()
        thermal = ThermalMonitor.read()

        if appMode == .auto, tickCount.isMultiple(of: Config.Timing.autopilotEveryTicks) {
            runAutopilot()
        }
        led.updateAutoColor(dieC: thermal.dieTemperatureC, autopilot: autopilot)

        // The cooler occasionally drops a write, so re-assert periodically —
        // cheap insurance against the UI and the hardware silently diverging.
        if ble.isConnected, tickCount.isMultiple(of: Config.Timing.heartbeatEveryTicks) {
            ble.reassertCurrentSettings()
        }

        refresh()
        writeStatusSnapshot()
    }

    /// Evaluates the autopilot and applies its decision, if anything changed.
    func runAutopilot() {
        let decision = autopilot.evaluate(thermalState: thermal.thermalState,
                                          dieC: thermal.dieTemperatureC,
                                          now: Date().timeIntervalSince1970)
        let tier = decision.tier
        guard tier.mode != ble.mode || tier.fanPercent != ble.fanPercent else { return }

        EventLogger.record("\(decision.reason)  → cooler \(tier.label), fan \(tier.fanPercent)%")
        ble.apply(mode: tier.mode, fanPercent: tier.fanPercent)
    }

    // ── Switching lockout ────────────────────────────────────────────────────

    /// Disables the controls for a moment after a change, then refreshes.
    /// Returns `false` if a change is already in flight, in which case the
    /// caller should do nothing.
    @discardableResult
    func beginSwitching() -> Bool {
        guard !isSwitching else { return false }
        isSwitching = true

        switchingTimer?.invalidate()
        let timer = Timer(timeInterval: Config.Timing.switchLockout, repeats: false) {
            [weak self] _ in
            self?.isSwitching = false
            self?.refresh()
        }
        // .common so the countdown continues while the menu tracks the mouse.
        RunLoop.main.add(timer, forMode: .common)
        switchingTimer = timer

        refresh()
        return true
    }

    // ── Termination ──────────────────────────────────────────────────────────

    /// Holds termination open until the Bluetooth link is fully torn down.
    ///
    /// A clean disconnect makes CoreBluetooth send the link-layer terminate, so
    /// the cooler frees its single connection slot immediately. Skip it and the
    /// device keeps believing we're connected until its supervision timeout —
    /// which blocks the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true

        guard ble != nil, ble.hasActiveLink else {
            EventLogger.record("app stop")
            return .terminateNow
        }

        EventLogger.record("app stopping — turning cooler off and disconnecting")

        // Leave the hardware in a safe state: manual mode must not keep the
        // cooler running after the app that controls it is gone.
        if ble.isConnected {
            ble.setMode(.off)
            ble.setFanPercent(0)
        }

        var replied = false
        let finish = {
            guard !replied else { return }
            replied = true
            EventLogger.record("app stop")
            NSApp.reply(toApplicationShouldTerminate: true)
        }

        // Reply once the disconnect actually completes…
        ble.onDisconnect = finish
        // …having given the off-writes time to flush first.
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.disconnectFlushDelay) {
            [weak self] in
            self?.ble.disconnect()
        }
        // Backstop, so quitting can never hang on a callback that never arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.Timing.terminationDeadline,
                                      execute: finish)

        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        IPCBridge.cleanUpRuntimeFiles()
    }
}
