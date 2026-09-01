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
        refreshSettingsItems(connected: connected, coolerOn: coolerOn)
        refreshStatusItemButton(coolerOn: coolerOn)
        refreshStatusCard(connected: connected)
    }

    // ── Update notice ────────────────────────────────────────────────────────

    /// Shows the update row only while a newer, unskipped release is known,
    /// narrating the automatic install as it runs. Independent of the
    /// connection state — an update matters whether or not a cooler is
    /// attached. Clicking the banner always opens the release page; while an
    /// install is in flight that is the only thing left to offer (the notes),
    /// and afterwards it is the fallback.
    private func refreshUpdateNotice() {
        let update = updates.available
        let installing = installer.state == .downloading || installer.state == .installing
        rows.updateBanner.isHidden = (update == nil)
        rows.updateSeparator.isHidden = (update == nil)
        // Skipping mid-install could not stop the swap already running; the
        // row bows out once the download starts.
        rows.skipUpdate.isHidden = (update == nil) || installing

        guard let update else { return }
        switch installer.state {
        case .downloading:
            updateBanner.configure(style: .info,
                                   text: "Downloading version \(update.displayVersion)…",
                                   symbol: "arrow.down.circle.fill",
                                   showSpinner: true)
        case .installing:
            updateBanner.configure(style: .info,
                                   text: "Installing version \(update.displayVersion)…",
                                   symbol: "arrow.down.circle.fill",
                                   showSpinner: true)
        case .failed:
            updateBanner.configure(style: .warning,
                                   text: "Update failed — open the release page",
                                   symbol: "exclamationmark.triangle.fill",
                                   showSpinner: false)
        case .idle:
            updateBanner.configure(style: .info,
                                   text: "Version \(update.displayVersion) available",
                                   symbol: "arrow.down.circle.fill",
                                   showSpinner: false)
        }
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

        // The LED panel's membership follows the effect, so which row rounds
        // it off has to be recomputed alongside the visibility above.
        applyPanelSegments(to: [
            (effectPicker, !rows.effect.isHidden),
            (breathToggle, !rows.breathToggle.isHidden),
            (colorPicker, !rows.color.isHidden),
        ])

        // Power items: "Turn Off" only while it's running, "Turn Off &
        // Disconnect" whenever we hold a link at all.
        rows.turnOff.isHidden = !coolerOn
        rows.turnOffAndDisconnect.isHidden = !connected

        // "Change Device" duplicates what the open picker already offers, so
        // it steps aside while the picker is on screen.
        rows.changeDevice.isHidden = isSelectingDevice
    }

    /// Hands each visible row its slice of the section panel — first rounds the
    /// top, last rounds the bottom, a sole survivor rounds both.
    private func applyPanelSegments(to rows: [(view: PanelRowView, visible: Bool)]) {
        let visible = rows.filter(\.visible).map(\.view)
        for (index, view) in visible.enumerated() {
            let top = (index == 0)
            let bottom = (index == visible.count - 1)
            view.panelSegment = top && bottom ? .only
                              : top ? .top
                              : bottom ? .bottom : .middle
        }
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

    private func refreshSettingsItems(connected: Bool, coolerOn: Bool) {
        startAtLoginRow.isChecked = LoginItem.isEnabled

        // Mirrors the isHidden decisions made for these rows elsewhere in this
        // file, so the panel's corners always land on the rows actually shown.
        applyPanelSegments(to: [
            (turnOffRow, coolerOn),
            (turnOffDisconnectRow, connected),
            (startAtLoginRow, true),
            (changeDeviceRow, !isSelectingDevice),
        ])
    }

    // ── Menu-bar button ──────────────────────────────────────────────────────

    private func refreshStatusItemButton(coolerOn: Bool) {
        guard let button = statusItem.button else { return }
        let temperature = ble.isConnected
            ? SystemInfo.formatTemp(thermal.dieTemperatureC, degreeOnly: true)
            : ""

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
