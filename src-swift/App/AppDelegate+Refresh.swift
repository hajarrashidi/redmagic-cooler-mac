import AppKit

/// Pushes current state into the UI.
///
/// One function drives every visual element, called after anything changes and
/// once a second from the tick. That's deliberate: with a menu this stateful,
/// scattered incremental updates are how rows end up contradicting each other.
/// Recomputing everything is cheap and always self-consistent.
extension AppDelegate {

    func refresh() {
        let connected = ble.isConnected
        let coolerOn = connected && ble.mode.isOn
        let isManual = (appMode == .manual)

        refreshControls(connected: connected, isManual: isManual)
        refreshVisibility(connected: connected, coolerOn: coolerOn, isManual: isManual)
        refreshSettingsItems()
        refreshStatusItemButton(coolerOn: coolerOn)
        refreshStatusCard(connected: connected)
    }

    // ── Control values ───────────────────────────────────────────────────────

    private func refreshControls(connected: Bool, isManual: Bool) {
        let enabled = !isSwitching

        modeSwitch.setMode(appMode)
        modeSwitch.setEnabled(enabled)

        autoOptions.configure(profile: autopilot.profile, engageC: autopilot.customEngageC)
        autoOptions.setEnabled(enabled)

        // While a switch is in flight the fan write hasn't landed yet, so
        // re-deriving the step here would briefly snap the thumb to a
        // neighbouring sub-step. Leave it where the user dropped it and re-sync
        // once the device has settled.
        if !isSwitching {
            coolingSlider.setStep(isManual
                ? CoolingSliderView.step(matching: ble.mode, fanPercent: ble.fanPercent)
                : 0)
        }
        coolingSlider.setEnabled(enabled)

        effectPicker.setSelected(led.effect)
        effectPicker.setEnabled(enabled)
        breathToggle.setStyle(led.breathStyle)
        breathToggle.setEnabled(enabled)
        colorPicker.setHue(led.hue)
    }

    // ── Row visibility ───────────────────────────────────────────────────────

    private func refreshVisibility(connected: Bool, coolerOn: Bool, isManual: Bool) {
        // Until the cooler connects, offer only a Connect button — every other
        // control is meaningless, and misleading, without a live link.
        rows.connect.isHidden = connected
        if !connected { refreshConnectItem() }

        rows.modeSwitch.isHidden = !connected
        rows.autoOptions.isHidden = !connected || isManual
        rows.coolingSlider.isHidden = !connected || !isManual
        rows.manualWarning.isHidden = !connected || !(isManual && coolerOn) || isSwitching
        rows.switchingBanner.isHidden = !connected || !isSwitching

        // LED controls only mean something while the cooler is running; when
        // it's off, swap them for an explanatory banner.
        rows.ledSeparator.isHidden = !connected
        rows.effect.isHidden = !coolerOn
        rows.breathToggle.isHidden = !coolerOn || led.effect != .breath
        rows.color.isHidden = !coolerOn || !led.usesPickedColor
        rows.ledOffBanner.isHidden = !connected || coolerOn

        // Power items: "Turn Off" only while it's running, "Turn Off &
        // Disconnect" whenever we hold a link at all.
        rows.turnOff.isHidden = !coolerOn
        rows.turnOffAndDisconnect.isHidden = !connected
    }

    /// Reflects the live connection phase, so the user never clicks "Connect"
    /// on top of an attempt already running — which used to cancel it.
    private func refreshConnectItem() {
        if let title = ble.phase.connectItemTitle {
            rows.connect.title = title
            rows.connect.action = nil
        } else {
            rows.connect.title = "Connect"
            rows.connect.action = #selector(connectDevice)
        }
    }

    private func refreshSettingsItems() {
        let style = MenuBarIndicator(
            persisted: UserDefaults.standard.string(forKey: Config.Key.indicatorStyle))
        for item in rows.indicatorStyle.submenu?.items ?? [] {
            let itemStyle = (item.representedObject as? String).map(MenuBarIndicator.init(rawValue:))
            item.state = (itemStyle == style) ? .on : .off
        }
        rows.startAtLogin.state = LoginItem.isEnabled ? .on : .off
    }

    // ── Menu-bar button ──────────────────────────────────────────────────────

    private func refreshStatusItemButton(coolerOn: Bool) {
        guard let button = statusItem.button else { return }
        let style = MenuBarIndicator(
            persisted: UserDefaults.standard.string(forKey: Config.Key.indicatorStyle))
        let temperature = ble.isConnected
            ? SystemInfo.formatTemp(thermal.dieTemperatureC, degreeOnly: true)
            : ""

        switch style {
        case .text:
            button.image = nil
            button.title = ble.isConnected
                ? (temperature.isEmpty ? "Magic" : "Magic \(temperature)")
                : ble.phase.menuBarText
            button.contentTintColor = nil

        case .icon:
            button.image = RedMagicLogo.image(size: 16, template: true)
            button.imagePosition = temperature.isEmpty ? .imageOnly : .imageLeading
            button.title = temperature.isEmpty ? "" : " \(temperature)"
            // Tinted only while actively cooling: a coloured glyph in the menu
            // bar should mean something is happening.
            if !ble.isConnected {
                button.contentTintColor = .tertiaryLabelColor
            } else if coolerOn {
                button.contentTintColor = UIStyle.heatColor(thermal.dieTemperatureC)
            } else {
                button.contentTintColor = nil
            }
        }
    }

    // ── Status card ──────────────────────────────────────────────────────────

    private func refreshStatusCard(connected: Bool) {
        statusCard.update(StatusCardView.ViewModel(
            dieTempC: thermal.dieTemperatureC,
            thermalState: thermal.thermalState,
            mode: ble.mode,
            telemetry: telemetry,
            isConnected: connected,
            phase: ble.phase,
            appMode: appMode,
            autoProfile: autopilot.profile,
            fanTint: led.fanTint(dieC: thermal.dieTemperatureC)))
    }

    // ── Status snapshot for the CLI ──────────────────────────────────────────

    func writeStatusSnapshot() {
        IPCBridge.write(StatusSnapshot(
            timestamp: Date().timeIntervalSince1970,
            state: ble.isConnected ? "on" : "connecting",
            level: appMode == .auto ? AppMode.auto.rawValue : ble.mode.slug,
            isAuto: appMode == .auto,
            fanPercent: Int(ble.fanPercent),
            modeName: ble.mode.slug,
            thermalState: thermal.thermalState.rawValue,
            cpuC: thermal.dieTemperatureC,
            profile: autopilot.profile.rawValue,
            led: led.lastWrittenColor.map { [Int($0.r), Int($0.g), Int($0.b)] },
            lightMode: ble.lightMode.map(Int.init),
            tempThreshold: ble.tempThreshold.map(Int.init),
            deviceAutoTemp: ble.deviceAutoTemp,
            mountAttached: mountAttached,
            coldC: telemetry?.coldC,
            hotC: telemetry?.hotC,
            ambientC: telemetry?.ambientC,
            fanRPM: telemetry?.fanRPM))
    }
}
