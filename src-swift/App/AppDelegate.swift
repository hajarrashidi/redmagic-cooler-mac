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
/// | `AppDelegate+BLE.swift`    | device callbacks                         |
///
/// The app is `.accessory`: no Dock icon, no main window, driven entirely from
/// the menu-bar item.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // ── Collaborators ────────────────────────────────────────────────────────

    var ble: CoolerBLEManager!
    var autopilot: AutopilotPolicy!
    var led: LedController!
    var updates: UpdateChecker!
    var installer: UpdateInstaller!

    // ── Menu ─────────────────────────────────────────────────────────────────

    var statusItem: NSStatusItem!
    var menu: NSMenu!

    /// Custom rows. Held so `refresh()` can update and show/hide them without
    /// rebuilding the menu, which would close it under the user's cursor.
    var statusCard: StatusCardView!
    var coolerPanel: CoolerPanelView!
    var updateBanner: BannerView!
    var devicePicker: DevicePickerView!
    var modeSwitch: ModeSwitchView!
    var autoOptions: AutoOptionsView!
    var turboStatus: TurboStatusView!
    var coolingSlider: CoolingSliderView!
    var manualTimerRow: ManualTimerView!
    var effectPicker: LedEffectPickerView!
    var breathToggle: BreathStyleToggleView!
    var colorPicker: HueSpectrumPickerView!
    var turnOffRow: MenuActionRow!
    var changeDeviceRow: MenuActionRow!
    var turnOffQuitRow: MenuActionRow!
    var skipUpdateRow: MenuActionRow!

    /// The menu items wrapping those rows, plus the plain items whose
    /// visibility depends on state.
    var rows: MenuRows!

    // ── State ────────────────────────────────────────────────────────────────

    /// Which control loop the user has selected. Distinct from the device's
    /// own mode: in `.auto` the autopilot writes the device mode, in `.manual`
    /// the slider does.
    var appMode: AppMode = .auto

    /// The auto-off clock for Manual. Armed whenever Manual is actually
    /// cooling; see `ManualTimer` for why Manual is the mode that needs one.
    var manualTimer = ManualTimer(timeout: .oneHour)
    /// The timer ran down and switched the cooler off, and the user has not
    /// touched anything since. Cleared by the next cooling command, so the
    /// panel says what happened exactly once.
    var manualTimedOut = false

    /// Latest thermal sample, refreshed each tick.
    var thermal = ThermalMonitor.Reading(thermalState: .nominal, dieTemperatureC: nil)

    /// Universal Hardware Safety Governor:
    /// Tripped when Mac die temperature drops below Config.Safety.condensationCutoffC (36.0°C).
    /// Re-arms only when die temperature reaches Config.Safety.condensationRearmC (38.0°C).
    var isSafetyGovernorActive: Bool = false

    /// Latest telemetry frame from the cooler, cleared when the link drops.
    var telemetry: CoolerTelemetry?
    /// Whether the magnetic mount is seated.
    var mountAttached: Bool?

    /// Infers the cooler's physical power switch being off while still linked.
    var switchMonitor = PhysicalSwitchMonitor()
    /// When the newest telemetry frame arrived, seeded at connect so silence
    /// from a device that never reports at all is still measurable.
    var lastTelemetryAt: TimeInterval?

    /// Discovery results are being shown inside the status menu until the user
    /// explicitly chooses one. This stays true even for a single result.
    var isSelectingDevice = false

    /// True briefly after a user-initiated change, while writes are in flight.
    /// Controls are disabled meanwhile so a second command can't race the first,
    /// and the slider is left alone so it doesn't snap away from where the user
    /// dropped it before the device has caught up.
    var isSwitching = false
    private var switchingTimer: Timer?
    private var pendingLedWorkItem: DispatchWorkItem?

    /// An update is downloading or being swapped in. The menu locks down for
    /// the duration: the app is about to be replaced and relaunched, and a
    /// command issued into that has nowhere to land.
    var isInstallingUpdate: Bool {
        installer.state == .downloading || installer.state == .installing
    }

    /// Set when the user explicitly asks to connect, so the cooler can be
    /// commanded off once the link is up — a known-safe starting state.
    var turnOffOnConnect = false

    /// Colour the menu-bar mark was last drawn in. The image is redrawn only
    /// when this changes, so the 1 Hz refresh doesn't churn the menu bar.
    var menuBarIconColor: NSColor?

    private var tickTimer: Timer?
    private var tickCount = 0

    /// Guards against `applicationShouldTerminate` running its teardown twice.
    private var isTerminating = false
    // ── Launch ───────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Deliberately no appearance override. The app used to pin itself to
        // Aqua on the grounds that its heat colours read best on white — but
        // the menu's own chrome is not the app's to pin, and follows the
        // system. On a dark desktop that left light-mode content on a dark
        // menu: black labels on near-black. Every colour the menu draws is
        // either a system colour or drawn from one, so following the system is
        // both correct and the only self-consistent option.

        // Hand the Bluetooth link over from any previous instance before doing
        // anything else — the cooler allows only one connection, so until the
        // old process exits this one cannot connect at all.
        SingleInstance.terminateOthersAndWait()

        loadSettings()

        ble = CoolerBLEManager()
        ble.delegate = self
        led = LedController(ble: ble)
        thermal = ThermalMonitor.read()
        evaluateSafetyGovernor(reapplyOnClear: false)

        // Built before the menu, which wires a banner straight to them. A
        // noticed release starts installing at once — the banner narrates the
        // download and install, and the app relaunches itself when they land.
        updates = UpdateChecker()
        installer = UpdateInstaller()
        installer.onChange = { [weak self] in self?.refresh() }
        // Noticing a release only surfaces the banner. Installing it swaps the
        // running app and relaunches it, which is not something to do to
        // someone mid-session without asking — see `installUpdateNow`.
        updates.onChange = { [weak self] in self?.refresh() }

        buildStatusItem()
        buildMenu()

        let timer = Timer(timeInterval: Config.Timing.poll, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(macWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(macDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(macWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        EventLogger.record("app start — mode=\(appMode.rawValue) ladder=50/60/65/70°C safety=<36°C")
        refresh()

        // The friendly Mac name needs system_profiler, which is far too slow to
        // block launch on; refresh the menu once it lands.
        SystemInfo.resolveModelName { [weak self] _ in self?.refresh() }

        // Every launch, deliberately unthrottled: opening the app is exactly
        // when a user wants to be brought current. One request per launch is
        // nothing against GitHub's unauthenticated budget, and it still stamps
        // the clock, so the periodic check below stays a day behind it.
        updates.check()

        if ble.hasKnownDevice {
            EventLogger.record("auto-connecting to preferred cooler on launch")
            ble.startScanning()
        }

        writeProbeSnapshot()
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        appMode = AppMode(persisted: defaults.string(forKey: Config.Key.appMode))
        manualTimer = ManualTimer(timeout: ManualTimer.Timeout(
            persisted: defaults.object(forKey: Config.Key.manualTimeout) as? Int))

        let engageC: Double
        if let saved = defaults.object(forKey: Config.Key.engageC) as? Double {
            engageC = saved
        } else if defaults.string(forKey: Config.Key.legacyAutoProfile) == "custom",
                  let legacy = defaults.object(forKey: Config.Key.legacyCustomEngageC) as? Double {
            // Preserve an actively selected Custom threshold. A legacy
            // Standard user gets the new threshold slider's default instead
            // of inheriting a previously hidden Custom value.
            engageC = legacy
        } else {
            engageC = Config.Autopilot.engageDefaultC
        }

        let shutoffC: Double
        if let saved = defaults.object(forKey: Config.Key.shutoffC) as? Double {
            shutoffC = saved
        } else {
            shutoffC = Config.Autopilot.shutoffDefaultC
        }

        let minFan: UInt8
        if let saved = defaults.object(forKey: Config.Key.smartMaxMinFan) as? Int {
            minFan = UInt8(clamping: saved)
        } else {
            minFan = Config.Autopilot.smartMaxMinFanDefault
        }

        autopilot = AutopilotPolicy(engageC: engageC, shutoffC: shutoffC, minFanPercent: minFan)
        if let savedProfile = defaults.string(forKey: "AutoProfile") {
            if let p = AutoProfile(rawValue: savedProfile) {
                autopilot.setProfile(p)
            } else if savedProfile == "Max Inteligente" || savedProfile == "maxIntel" {
                autopilot.setProfile(.smartMax)
            } else if savedProfile == "Equilibrado" {
                autopilot.setProfile(.balanced)
            }
        }
        defaults.set(autopilot.engageC, forKey: Config.Key.engageC)
        defaults.set(autopilot.shutoffC, forKey: Config.Key.shutoffC)
        defaults.set(Int(autopilot.minFanPercent), forKey: Config.Key.smartMaxMinFan)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
    }

    // ── Tick ─────────────────────────────────────────────────────────────────

    /// The master loop, once a second: sample temperature, run the autopilot,
    /// re-assert device state, refresh the UI, and refresh developer probe data.
    private func tick() {
        tickCount += 1

        handlePendingProbeCommand()
        thermal = ThermalMonitor.read()
        updateSwitchMonitor()
        expireManualTimerIfDue()
        evaluateSafetyGovernor()

        if !isSafetyGovernorActive {
            if appMode == .auto, tickCount.isMultiple(of: Config.Timing.autopilotEveryTicks) {
                runAutopilot()
            }
        }
        if pendingLedWorkItem == nil {
            led.updateAutoColor(dieC: thermal.dieTemperatureC, autopilot: autopilot)
        }

        // The cooler occasionally drops a write, so re-assert periodically —
        // cheap insurance against the UI and the hardware silently diverging.
        if ble.isConnected, tickCount.isMultiple(of: Config.Timing.heartbeatEveryTicks) {
            if !isSafetyGovernorActive {
                ble.reassertCurrentSettings()
                led.reapply(dieC: thermal.dieTemperatureC, autopilot: autopilot)
            } else if ble.mode != .off || ble.fanPercent != 0 {
                ble.apply(mode: .off, fanPercent: 0)
            }
        }

        // Only so an app left running for days still notices a release; the
        // once-a-day throttle lives in UpdateChecker.
        if tickCount.isMultiple(of: Config.Timing.updateCheckEveryTicks) {
            updates.checkIfDue()
        }

        refresh()
        writeProbeSnapshot()
    }

    /// Evaluates the universal condensation safety barrier across ALL modes.
    /// Trips at < 36.0°C and re-arms at >= 38.0°C.
    private func evaluateSafetyGovernor(reapplyOnClear: Bool = true) {
        guard let dieC = thermal.dieTemperatureC else { return }

        if !isSafetyGovernorActive {
            if dieC < Config.Safety.condensationCutoffC {
                isSafetyGovernorActive = true
                EventLogger.record("🛡️ Safety Governor tripped: die temp \(String(format: "%.1f", dieC))°C < \(Config.Safety.condensationCutoffC)°C — forcing Standby across \(appMode.rawValue) mode to prevent condensation")
                if ble != nil && ble.isConnected {
                    ble.apply(mode: .off, fanPercent: 0)
                }
            }
        } else {
            // Already active: check re-arm threshold
            if dieC >= Config.Safety.condensationRearmC {
                isSafetyGovernorActive = false
                EventLogger.record("🛡️ Safety Governor cleared: die temp \(String(format: "%.1f", dieC))°C >= \(Config.Safety.condensationRearmC)°C — re-arming \(appMode.rawValue) mode")
                if reapplyOnClear {
                    reapplyActiveMode()
                }
            } else {
                // Ensure device remains off while governor is active
                if ble != nil && ble.isConnected && (ble.mode != .off || ble.fanPercent != 0) {
                    ble.apply(mode: .off, fanPercent: 0)
                }
            }
        }
    }

    /// Re-applies active mode settings when safety governor disengages.
    func reapplyActiveMode() {
        guard !isSafetyGovernorActive else { return }
        if appMode == .auto {
            autopilot.resetStandby(isStandby: true)
        }
        syncHardwareToActiveMode(force: true)
    }

    /// Synchronizes the connected cooler's hardware state with `appMode`
    /// (on connect, reconnect, wake from sleep, or Safety Governor re-arm).
    func syncHardwareToActiveMode(force: Bool = false) {
        guard ble != nil, ble.isConnected else { return }
        expireManualTimerIfDue()
        let wasSafetyActive = isSafetyGovernorActive
        evaluateSafetyGovernor(reapplyOnClear: false)
        if wasSafetyActive && !isSafetyGovernorActive && appMode == .auto {
            autopilot.resetStandby(isStandby: true)
        }

        if isSafetyGovernorActive {
            ble.apply(mode: .off, fanPercent: 0)
            scheduleLedReassertion()
            return
        }

        switch appMode {
        case .auto:
            runAutopilot(force: force)
        case .manual:
            let rawStep = UserDefaults.standard.object(forKey: Config.Key.manualStep) as? Int ?? 0
            let index = rawStep.clamped(to: CoolingSliderView.indexRange)
            let step = CoolingSliderView.steps[index]
            if step.mode.isOn && !manualTimedOut {
                if manualTimer.deadline == nil && manualTimer.timeout != .unlimited {
                    manualTimer.start()
                }
                ble.apply(mode: step.mode, fanPercent: step.fanPercent)
            } else {
                ble.apply(mode: .off, fanPercent: 0)
            }
            scheduleLedReassertion()
        case .turbo:
            ble.apply(mode: .max, fanPercent: 100)
            scheduleLedReassertion()
        }
    }

    /// Evaluates the autopilot and applies its decision, if anything changed (or if forced).
    func runAutopilot(force: Bool = false) {
        guard ble != nil, ble.isConnected, !isSafetyGovernorActive else { return }
        let decision = autopilot.evaluate(thermalState: thermal.thermalState,
                                          dieC: thermal.dieTemperatureC,
                                          now: Date().timeIntervalSince1970)
        let tier = decision.tier
        guard force || tier.mode != ble.mode || tier.fanPercent != ble.fanPercent else { return }

        EventLogger.record("\(decision.reason)  → cooler \(tier.label), fan \(tier.fanPercent)%")
        ble.apply(mode: tier.mode, fanPercent: tier.fanPercent)
        scheduleLedReassertion()
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

    /// Invalidates LED cache and schedules a clean re-assertion after BLE mode/fan writes settle.
    /// This cures hardware firmware resets that revert the LED to default red on mode switches.
    func scheduleLedReassertion(delay: TimeInterval = 0.45) {
        pendingLedWorkItem?.cancel()
        led.invalidateCache()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.led.reapply(dieC: self.thermal.dieTemperatureC, autopilot: self.autopilot)
            self.pendingLedWorkItem = nil
        }
        pendingLedWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // ── Sleep / Wake Lifecycle ───────────────────────────────────────────────

    @objc private func macWillSleep() {
        EventLogger.record("system will sleep — turning cooler off")
        if ble != nil && ble.isConnected {
            ble.apply(mode: .off, fanPercent: 0)
        }
    }

    @objc private func macDidWake() {
        EventLogger.record("system did wake — restoring active cooling mode (\(appMode.rawValue))")
        thermal = ThermalMonitor.read()
        syncHardwareToActiveMode(force: true)
        refresh()
    }

    @objc private func macWillPowerOff(_ notification: Notification) {
        EventLogger.record("system shutting down / power off — turning cooler off")
        if ble != nil && ble.isConnected {
            ble.apply(mode: .off, fanPercent: 0)
        }
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
        // cooler running after the app that controls it is gone. Via apply, so
        // the fan write is spaced clear of the mode write and actually lands.
        if ble.isConnected {
            ble.apply(mode: .off, fanPercent: 0)
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
        cleanUpProbeFiles()
    }
}
