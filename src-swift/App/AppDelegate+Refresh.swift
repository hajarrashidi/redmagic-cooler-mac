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

        refreshUpdateNotice()
        refreshControls(isManual: isManual)
        refreshVisibility(connected: connected, coolerOn: coolerOn, isManual: isManual)
        refreshSettingsItems()
        refreshStatusItemButton(coolerOn: coolerOn)
        refreshStatusCard(connected: connected)
    }

    // ── Update notice ────────────────────────────────────────────────────────

    /// Shows the update row only while a newer, unskipped release is known.
    /// Independent of the connection state — a pending update is worth seeing
    /// whether or not a cooler is attached.
    private func refreshUpdateNotice() {
        let update = updates.available
        rows.updateBanner.isHidden = (update == nil)
        rows.skipUpdate.isHidden = (update == nil)
        rows.updateSeparator.isHidden = (update == nil)

        guard let update else { return }
        updateBanner.configure(style: .info,
                               text: "Version \(update.displayVersion) available",
                               symbol: "arrow.down.circle.fill",
                               showSpinner: false)
    }

    // ── Control values ───────────────────────────────────────────────────────

    private func refreshControls(isManual: Bool) {
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
        // Discovery choices replace the Connect item in-place. Keeping both in
        // the same menu avoids opening a separate chooser window, while every
        // result still requires an explicit click.
        rows.connect.isHidden = connected || isSelectingDevice
        rows.devicePicker.isHidden = connected || !isSelectingDevice
        if !connected && !isSelectingDevice { refreshConnectItem() }

        rows.modeSwitch.isHidden = !connected
        rows.autoOptions.isHidden = !connected || isManual
        rows.coolingSlider.isHidden = !connected || !isManual
        let deviceOff = connected && switchMonitor.looksPoweredOff
        rows.deviceOffBanner.isHidden = !deviceOff

        // The manual reminder is about the cooler staying on. While its own
        // switch is off it is not on, and stacking two warnings would bury the
        // one that actually explains what the user is seeing.
        rows.manualWarning.isHidden =
            !connected || !(isManual && coolerOn) || isSwitching || deviceOff
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

    /// The persisted menu-bar style, read fresh on every refresh so the
    /// submenu's checkmark and the button itself can never disagree.
    private var menuBarStyle: MenuBarIndicator {
        MenuBarIndicator(
            persisted: UserDefaults.standard.string(forKey: Config.Key.indicatorStyle))
    }

    private func refreshSettingsItems() {
        let style = menuBarStyle
        for item in rows.indicatorStyle.submenu?.items ?? [] {
            let itemStyle = (item.representedObject as? String).map(MenuBarIndicator.init(rawValue:))
            item.state = (itemStyle == style) ? .on : .off
        }
        rows.startAtLogin.state = LoginItem.isEnabled ? .on : .off
    }

    // ── Menu-bar button ──────────────────────────────────────────────────────

    private func refreshStatusItemButton(coolerOn: Bool) {
        guard let button = statusItem.button else { return }
        let style = menuBarStyle
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
            button.imagePosition = temperature.isEmpty ? .imageOnly : .imageLeading
            button.title = temperature.isEmpty ? "" : " \(temperature)"

            // Drawn in its final colour rather than tinted: macOS manages the
            // tint of *template* images in the menu bar itself and ignores
            // contentTintColor there, so a template mark can't be forced white.
            //
            // White by default, heat-graded while the cooler is actually
            // running — so a coloured mark always means something is happening
            // — and dimmed while there's no link.
            let markColor: NSColor
            if !ble.isConnected {
                markColor = NSColor.white.withAlphaComponent(0.55)
            } else if coolerOn {
                markColor = UIStyle.heatColor(thermal.dieTemperatureC)
            } else {
                markColor = .white
            }

            if markColor != menuBarIconColor {
                menuBarIconColor = markColor
                button.image = RedMagicLogo.image(size: 16, color: markColor)
            }
            button.contentTintColor = nil
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
            deviceModelName: ble.profile?.modelName,
            appMode: appMode,
            autoProfile: autopilot.profile,
            fanTint: led.fanTint(dieC: thermal.dieTemperatureC),
            deviceLooksPoweredOff: switchMonitor.looksPoweredOff))
    }

}
