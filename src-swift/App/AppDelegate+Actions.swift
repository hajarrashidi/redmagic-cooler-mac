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
            runAutopilot()

        case .manual:
            // Entering Manual should actually cool. If the remembered level is
            // Off — never set, or left off last time — fall back to a mid step
            // rather than switching to a mode that does nothing.
            var step = UserDefaults.standard.object(forKey: Config.Key.manualStep) as? Int
                ?? CoolingSliderView.defaultStep
            if step <= 0 { step = CoolingSliderView.defaultStep }
            EventLogger.record("switch → manual")
            applyManualStep(step, alreadySwitching: true)
        }
        refresh()
    }

    func selectAutoProfile(_ profile: AutoProfile) {
        guard beginSwitching() else { return }
        autopilot.setProfile(profile)
        UserDefaults.standard.set(profile.rawValue, forKey: Config.Key.autoProfile)
        EventLogger.record("auto profile → \(profile.rawValue)")
        runAutopilot()
        refresh()
    }

    /// Fires continuously while the engage slider moves, so it deliberately
    /// skips the switching lockout — the autopilot simply re-evaluates against
    /// the new threshold on each change.
    func setCustomEngage(_ celsius: Double) {
        autopilot.setCustomEngage(celsius)
        UserDefaults.standard.set(autopilot.customEngageC, forKey: Config.Key.customEngageC)
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
        let index = index.clamped(to: CoolingSliderView.indexRange)
        let step = CoolingSliderView.steps[index]

        setAppMode(.manual)
        UserDefaults.standard.set(index, forKey: Config.Key.manualStep)

        ble.apply(mode: step.mode, fanPercent: step.fanPercent)
        EventLogger.record("manual → \(step.name)")
        refresh()
    }

    @objc func turnOff() {
        guard beginSwitching() else { return }
        setAppMode(.manual)
        UserDefaults.standard.set(0, forKey: Config.Key.manualStep)
        ble.apply(mode: .off, fanPercent: 0)
        EventLogger.record("manual → off")
        refresh()
    }

    /// Turns the cooler off and drops the Bluetooth link, leaving the app idle
    /// until the user reconnects. Frees the cooler's single connection slot —
    /// needed before the phone app can pair with it.
    @objc func turnOffAndDisconnect() {
        setAppMode(.manual)
        UserDefaults.standard.set(0, forKey: Config.Key.manualStep)

        guard ble.isConnected else {
            EventLogger.record("disconnect (user)")
            ble.disconnectAndStop()
            refresh()
            return
        }

        // Command off first, then drop the link once both writes have
        // flushed — apply spaces the fan write clear of the mode change.
        ble.apply(mode: .off, fanPercent: 0)
        EventLogger.record("manual → off + disconnect (user)")
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.BLE.disconnectFlushDelay) {
            [weak self] in
            self?.ble.disconnectAndStop()
        }
        refresh()
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
        turnOffOnConnect = true
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
        devicePicker.setScanning(true)
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
        turnOffOnConnect = true
        ble.connect(to: device)
        EventLogger.record("device selected: \(profile.modelName)")
        refresh()
    }

    /// Opens the porting guide, for someone whose cooler the app can see but
    /// has no profile for.
    func openAddingDevicesGuide() {
        NSWorkspace.shared.open(Config.Links.addingDevices)
        EventLogger.record("adding-devices guide opened")
    }

    // ── Updates ──────────────────────────────────────────────────────────────

    /// Kicks off installing whatever release the checker has on offer.
    ///
    /// Wired to `updates.onChange`, so a new release starts installing the
    /// moment it is noticed — at launch, or from the daily check of an app
    /// left running. `install` itself refuses re-entry mid-flight and skips
    /// releases without a DMG, so calling on every change is safe; a release
    /// the user skipped never reaches `available` in the first place.
    func installAvailableUpdate() {
        guard let update = updates.available else { return }
        installer.install(update)
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

    // ── Settings ─────────────────────────────────────────────────────────────

    @objc func toggleStartAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        refresh()
    }

    @objc func quitApp() {
        NSApp.terminate(self)
    }
}
