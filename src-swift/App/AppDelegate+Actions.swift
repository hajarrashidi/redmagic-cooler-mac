import AppKit

/// User-initiated changes, from menu items and the custom control rows.
///
/// Every action that writes to the cooler funnels through `beginSwitching()`
/// first, which both rejects a second change while one is in flight and
/// disables the controls until the device has caught up.
extension AppDelegate {

    // ── Cooling ──────────────────────────────────────────────────────────────

    func selectMode(_ mode: AppMode) {
        guard beginSwitching() else { return }
        setAppMode(mode)

        switch mode {
        case .auto:
            // Evaluate immediately rather than waiting for the next autopilot
            // tick, so the cooler follows the temperature the moment Auto is
            // chosen instead of holding the manual level for a few seconds.
            EventLogger.record("switch → auto")
            // Auto backs itself off as the Mac cools, so it needs no deadline.
            manualTimer.stop()
            manualTimedOut = false
            runAutopilot()

        case .manual:
            manualTimedOut = false
            // Entering Manual should actually cool. If the remembered level is
            // Off — never set, or left off last time — fall back to a mid step
            // rather than switching to a mode that does nothing.
            var step = UserDefaults.standard.object(forKey: Config.Key.manualStep) as? Int
                ?? activeProfile.defaultManualStep
            if step <= 0 { step = activeProfile.defaultManualStep }
            EventLogger.record("switch → manual")
            applyManualStep(step, alreadySwitching: true)
        }
        refresh()
    }

    /// Fires continuously while the engage slider moves, so it deliberately
    /// skips the switching lockout — the autopilot simply re-evaluates against
    /// the new threshold on each change.
    func setEngage(_ celsius: Double) {
        autopilot.setEngage(celsius)
        UserDefaults.standard.set(autopilot.engageC, forKey: Config.Key.engageC)
        if appMode == .auto { runAutopilot() }
        refresh()
    }

    /// The profile of the connected model, or the 6 Pro's before any is chosen,
    /// so the slider always has a layout to show.
    var activeProfile: DeviceProfile { ble.profile ?? .vcCooler6Pro }

    // ── Temperature source and Auto curve ────────────────────────────────────

    func showTemperatureSourceWindow() {
        let window = temperatureSourceWindow ?? TemperatureSourceWindow(current: temperatureSource)
        window.onSelect = { [weak self] in self?.setTemperatureSource($0) }
        temperatureSourceWindow = window
        window.show(current: temperatureSource)
    }

    func setTemperatureSource(_ source: ThermalMonitor.Source) {
        temperatureSource = source
        UserDefaults.standard.set(source.stored, forKey: Config.Key.temperatureSource)
        EventLogger.record("temperature source → \(source.title)")
        thermal = ThermalMonitor.read(source: source)
        if appMode == .auto { runAutopilot() }
        refresh()
    }

    func showPlateLimitWindow() {
        let window = plateLimitWindow ?? PlateLimitWindow()
        window.onSave = { [weak self] in self?.setPlateLimit(enabled: $0, floorC: $1) }
        plateLimitWindow = window
        window.show(enabled: plateLimitOn, floorC: plateLimitC)
    }

    func setPlateLimit(enabled: Bool, floorC: Double) {
        let defaults = UserDefaults.standard
        plateLimitOn = enabled
        plateLimitC = floorC.clamped(to: Config.PlateLimit.minC...Config.PlateLimit.maxC)
        defaults.set(plateLimitOn, forKey: Config.Key.plateLimitOn)
        defaults.set(plateLimitC, forKey: Config.Key.plateLimitC)
        EventLogger.record(enabled
            ? "plate limit → hold cooling back below \(Int(plateLimitC.rounded()))°C"
            : "plate limit → off")
        // Re-judge at once instead of waiting for the next tick.
        updatePlateGuard()
        refresh()
    }

    func showAutoCurveWindow() {
        let defaults = UserDefaults.standard
        let window = autoCurveWindow ?? AutoCurveWindow()
        window.onSave = { [weak self] in self?.applyCustomCurve(enabled: $0, temperaturesC: $1) }
        autoCurveWindow = window

        // One stage per step of the connected cooler, so the curve can use all
        // of them: the 8 Pro's eight levels and Diablo, or the 6 Pro's nine.
        let stages = activeProfile.curveStages
        let saved = (defaults.array(forKey: Config.Key.customCurveC) as? [Double])
            .flatMap { AutopilotPolicy.isValidCurve($0, stages: stages.count) ? $0 : nil }
        let fallback = AutopilotPolicy.spreadCurve(engageC: autopilot.engageC, stages: stages.count)
        window.show(stageNames: stages.map(\.name),
                    enabled: autopilot.customCurveC != nil,
                    curveC: autopilot.customCurveC ?? saved ?? fallback,
                    defaultCurveC: fallback)
    }

    /// Puts the saved custom curve in force, if one is switched on and fits the
    /// connected cooler (a curve has one point per stage, so it belongs to a
    /// model with that many). Otherwise the ladder from the threshold slider
    /// applies. Called at launch, on connect and after a save, since each can
    /// change which cooler it is for.
    func syncCustomCurve() {
        let defaults = UserDefaults.standard
        let saved = defaults.array(forKey: Config.Key.customCurveC) as? [Double]
        let usable = defaults.bool(forKey: Config.Key.customCurveOn)
            && saved.map { AutopilotPolicy.isValidCurve($0, stages: activeProfile.curveStages.count) } == true
        autopilot.setCustomCurve(usable ? saved : nil)
    }

    func applyCustomCurve(enabled: Bool, temperaturesC: [Double]) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: Config.Key.customCurveOn)
        if AutopilotPolicy.isValidCurve(temperaturesC, stages: activeProfile.curveStages.count) {
            defaults.set(temperaturesC, forKey: Config.Key.customCurveC)
        }
        syncCustomCurve()
        let summary = temperaturesC.map { String(format: "%.0f", $0) }.joined(separator: "/")
        EventLogger.record(enabled ? "auto curve → custom \(summary)°C" : "auto curve → default ladder")
        if appMode == .auto { runAutopilot() }
        refresh()
    }

    /// Applies a manual slider position.
    ///
    /// - Parameter alreadySwitching: set when called from `selectMode`, which
    ///   has already taken the lockout — taking it twice would abort the call.
    func applyManualStep(_ index: Int, alreadySwitching: Bool = false) {
        if !alreadySwitching {
            guard beginSwitching() else { return }
        }
        // Persist the clamped index too, so a bad value can't round-trip
        // through UserDefaults and come back out of range.
        let steps = activeProfile.manualSteps
        let index = index.clamped(to: 0...(steps.count - 1))
        let step = steps[index]

        setAppMode(.manual)
        UserDefaults.standard.set(index, forKey: Config.Key.manualStep)

        // Restarted on every command, not just on entering Manual. Someone
        // working the slider has plainly not forgotten the cooler, and cutting
        // them off mid-session on a clock they started an hour ago would be the
        // timer punishing exactly the user it isn't for.
        manualTimedOut = false
        if step.mode.isOn {
            manualTimer.start()
        } else {
            manualTimer.stop()
        }

        ble.apply(mode: step.mode, fanPercent: step.fanPercent, boost: step.boost)
        EventLogger.record("manual → \(step.name)")
        refresh()
    }

    // ── Manual auto-off ──────────────────────────────────────────────────────

    /// Applies a new limit, asking first when it is "no limit at all".
    ///
    /// The confirmation is the point of the feature: a timer that can be
    /// removed with one unremarkable click on a segmented control is a timer
    /// most people will remove by accident.
    func setManualTimeout(_ timeout: ManualTimer.Timeout) {
        guard timeout == .unlimited else {
            applyManualTimeout(timeout)
            return
        }
        // The menu has already dismissed itself — a modal cannot open under a
        // tracking menu — so the alert goes up on the next turn of the loop.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.confirmUnlimitedManual() {
                self.applyManualTimeout(.unlimited)
            } else {
                // Nothing to undo: the stored timeout never changed, and
                // refresh puts the control back where it was.
                self.refresh()
            }
        }
    }

    private func applyManualTimeout(_ timeout: ManualTimer.Timeout) {
        manualTimer.setTimeout(timeout, running: appMode == .manual && ble.mode.isOn)
        UserDefaults.standard.set(timeout.rawValue, forKey: Config.Key.manualTimeout)
        EventLogger.record("manual auto-off → \(timeout.label)")
        refresh()
    }

    private func confirmUnlimitedManual() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Run Manual cooling with no time limit?"
        alert.informativeText =
            "Manual will then keep the cooler running until you turn it off. "
            + "A thermoelectric plate held below room temperature for hours "
            + "draws moisture out of the air onto itself, and it does that "
            + "whether or not you are at the Mac. The auto-off timer is what "
            + "normally ends a session you forget about."
        alert.addButton(withTitle: "Remove the Limit")
        alert.addButton(withTitle: "Keep the Timer")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Ends a Manual session that has run its course.
    ///
    /// Deliberately stops at "off" rather than handing back to Auto. The whole
    /// premise is that nobody is watching, and Auto would read the temperature
    /// and start the cooler up again within seconds — which is the one outcome
    /// a user who set a one-hour limit did not ask for.
    func expireManualTimerIfDue() {
        guard appMode == .manual, ble.mode.isOn, manualTimer.hasExpired() else { return }
        manualTimer.stop()
        manualTimedOut = true
        UserDefaults.standard.set(0, forKey: Config.Key.manualStep)
        ble.apply(mode: .off, fanPercent: 0)
        EventLogger.record("manual auto-off timer expired → cooler off")
        refresh()
    }

    @objc func turnOff() {
        guard beginSwitching() else { return }
        setAppMode(.manual)
        manualTimer.stop()
        manualTimedOut = false
        UserDefaults.standard.set(0, forKey: Config.Key.manualStep)
        ble.apply(mode: .off, fanPercent: 0)
        EventLogger.record("manual → off")
        refresh()
    }

    /// Turns the cooler off and quits — the app's way out, and the only one.
    ///
    /// The hardware work is `applicationShouldTerminate`'s: it commands the
    /// cooler off and waits for a clean disconnect before letting the process
    /// go, because a cooler left running after its controller exits keeps
    /// running with nothing to stop it. All that's left here is to record the
    /// off state, so the next launch doesn't restore a level the user has just
    /// asked to end.
    @objc func turnOffAndQuit() {
        setAppMode(.manual)
        UserDefaults.standard.set(0, forKey: Config.Key.manualStep)
        EventLogger.record("turn off & quit (user)")
        NSApp.terminate(self)
    }

    /// Sets and persists the active control loop.
    private func setAppMode(_ mode: AppMode) {
        appMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Config.Key.appMode)
    }

    // ── LED ──────────────────────────────────────────────────────────────────

    func applyLedEffect(_ effect: LedEffect) {
        guard !isSwitching else { return }
        led.setEffect(effect)
        refresh()
    }

    func applyBreathStyle(_ style: BreathStyle) {
        guard !isSwitching else { return }
        led.setBreathStyle(style)
        refresh()
    }

    /// Fires continuously as the hue bar is dragged; no lockout, since these
    /// are cheap colour writes rather than mode changes.
    func applyLedHue(_ hue: Double) {
        led.setHue(hue)
        refresh()
    }

    // ── Connection ───────────────────────────────────────────────────────────

    @objc func connectDevice() {
        // Restarting the scan during an in-flight attempt cancels that attempt.
        // Let it finish instead.
        guard !ble.phase.isBusy else { return }

        // Reconnect to the saved cooler and, once linked, command it off as a
        // known starting state — see `turnOffOnConnect`. Deliberately *not*
        // resetForRescan(), which forgets the device; that's "Change Device".
        prepareForExplicitConnection()
        ble.startScanning()
        EventLogger.record("connect requested")
        refresh()
    }

    @objc func changeDevice() {
        UserDefaults.standard.removeObject(forKey: Config.Key.preferredDevice)
        scanAgainForDevices()
    }

    /// Enters the inline picker state and starts discovery over. The picker is
    /// an ordinary row in the status menu, so no separate app window appears.
    func scanAgainForDevices() {
        isSelectingDevice = true
        ble.resetForRescan()
        ble.startScanning()
        EventLogger.record("device scan requested")
        refresh()
    }

    /// Connects only after an explicit click on a discovered device row.
    ///
    /// Unsupported rows are unclickable in the picker and refused again by the
    /// manager, so `profile` is non-nil in practice; the guard keeps this
    /// honest rather than force-unwrapping a promise made two layers away.
    func selectDiscoveredDevice(_ device: CoolerBLEManager.DiscoveredDevice) {
        guard let profile = device.profile else { return }
        isSelectingDevice = false
        prepareForExplicitConnection()
        ble.connect(to: device)
        EventLogger.record("device selected: \(profile.modelName)")
        refresh()
    }

    /// A fresh user-requested connection always starts in Auto. The switch is
    /// hidden until the link is ready, so Auto is the first state they see.
    private func prepareForExplicitConnection() {
        turnOffOnConnect = true
        setAppMode(.auto)
    }

    /// Brings the Bluetooth adapter up for the first time, which is what makes
    /// macOS ask. Nothing else in the app touches Bluetooth before this, so the
    /// prompt only ever appears in answer to a press of "Allow Bluetooth
    /// Access" — never on top of a menu the user has only just opened.
    func requestBluetoothAccess() {
        ble.requestPermission()
        EventLogger.record("bluetooth permission requested")
        refresh()
    }

    /// The recovery path once access has been refused: nothing the app does can
    /// re-ask, so hand the user straight to the pane that can.
    func openBluetoothSettings() {
        NSWorkspace.shared.open(Config.Links.bluetoothPrivacySettings)
        EventLogger.record("bluetooth settings opened")
    }

    /// Opens the porting guide, for someone whose cooler the app can see but
    /// has no profile for.
    func openAddingDevicesGuide() {
        NSWorkspace.shared.open(Config.Links.addingDevices)
        EventLogger.record("adding-devices guide opened")
    }

    // ── Updates ──────────────────────────────────────────────────────────────

    /// Installs the offered release — on a click, and only on a click.
    ///
    /// This used to run the moment a release was noticed, which meant the app
    /// replaced itself and relaunched while someone was using it. Noticing a
    /// release now only raises the banner; pressing it lands here.
    ///
    /// The cooler is commanded off first. The install swaps the running app and
    /// restarts it, and for the seconds in between there is nothing driving the
    /// hardware — the same reason quitting turns it off.
    func installUpdateNow() {
        guard let update = updates.available else { return }
        // Nothing left to install; the banner's remaining job is the notes.
        if installer.state == .failed {
            openReleasePage()
            return
        }
        guard installer.state == .idle else { return }

        if ble.isConnected {
            setAppMode(.manual)
            UserDefaults.standard.set(0, forKey: Config.Key.manualStep)
            ble.apply(mode: .off, fanPercent: 0)
        }
        EventLogger.record("update install requested: \(update.tag)")
        installer.install(update)
        refresh()
    }

    /// Opens the release page in the browser — the update banner's click, and
    /// the fallback when an install fails or a release ships without a DMG.
    func openReleasePage() {
        guard let update = updates.available else { return }
        NSWorkspace.shared.open(update.page)
        EventLogger.record("update page opened: \(update.tag)")
    }

    @objc func skipThisVersion() {
        updates.skipAvailable()
        refresh()
    }

}
