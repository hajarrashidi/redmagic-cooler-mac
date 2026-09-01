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
        // The picker and the cooler panel are alternatives, each taking the
        // other's place. The picker wins whenever the user asked for it *and*
        // whenever no cooler has ever been chosen — with nothing saved, a panel
        // offering "Connect" would be offering a button with no destination.
        //
        // An attempt already in flight overrides both: between picking a device
        // and the link coming up nothing is saved yet, and dropping back to the
        // picker there would hide the "Connecting…" the user just asked for.
        let pickingDevice = !connected && !ble.phase.isBusy
                         && (isSelectingDevice || !ble.hasKnownDevice)

        refreshUpdateNotice()
        refreshControls(isManual: isManual)
        refreshVisibility(connected: connected, coolerOn: coolerOn, isManual: isManual,
                          pickingDevice: pickingDevice)
        refreshSettingsItems(connected: connected, coolerOn: coolerOn,
                             pickingDevice: pickingDevice)
        refreshStatusItemButton(coolerOn: coolerOn)
        refreshCards(connected: connected)
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

        autoOptions.configure(engageC: autopilot.engageC)
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

        // The picker narrates discovery entirely from these two, so it stays
        // truthful about scans that end without a result — including ones that
        // never start, because the adapter is off or was never allowed.
        devicePicker.setState(phase: ble.phase, permission: ble.permission)

        effectPicker.setSelected(led.effect)
        effectPicker.setEnabled(enabled)
        breathToggle.setStyle(led.breathStyle)
        breathToggle.setEnabled(enabled)
        colorPicker.setHue(led.hue)
    }

    // ── Row visibility ───────────────────────────────────────────────────────

    private func refreshVisibility(connected: Bool, coolerOn: Bool, isManual: Bool,
                                   pickingDevice: Bool) {
        // Keeping the picker inside the status menu avoids a separate chooser
        // window, while every result still requires an explicit click.
        rows.devicePicker.isHidden = !pickingDevice
        rows.coolerPanel.isHidden = pickingDevice

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

        // LED controls only mean something while the cooler is running — its
        // LED cannot show a colour when it isn't.
        rows.effect.isHidden = !coolerOn
        rows.breathToggle.isHidden = !coolerOn || led.effect != .breath
        rows.color.isHidden = !coolerOn || !led.usesPickedColor

        // An idle cooler under Auto is the autopilot working correctly, but it
        // is indistinguishable from a broken one until someone says so. Only
        // while nothing more urgent is on screen: a cooler whose own switch is
        // off is idle for a very different reason.
        let autoWaiting = connected && appMode == .auto && !coolerOn
                       && !isSwitching && !deviceOff
        rows.autoWaitingBanner.isHidden = !autoWaiting
        if autoWaiting {
            autoWaitingBanner.configure(
                style: .neutral,
                text: "Waiting for the Mac to reach \(Int(autopilot.engageC))°C",
                symbol: "thermometer.medium",
                showSpinner: false)
        }

        // Cooling and LED effect form one cooler-control panel. Membership
        // follows the active mode and effect, so recompute all panel corners.
        applyPanelSegments(to: [
            (modeSwitch, !rows.modeSwitch.isHidden),
            (autoOptions, !rows.autoOptions.isHidden),
            (coolingSlider, !rows.coolingSlider.isHidden),
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
        rows.changeDevice.isHidden = pickingDevice
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

    private func refreshSettingsItems(connected: Bool, coolerOn: Bool,
                                      pickingDevice: Bool) {
        startAtLoginRow.isChecked = LoginItem.isEnabled

        // Mirrors the isHidden decisions made for these rows elsewhere in this
        // file, so the panel's corners always land on the rows actually shown.
        applyPanelSegments(to: [
            (turnOffRow, coolerOn),
            (turnOffDisconnectRow, connected),
            (startAtLoginRow, true),
            (changeDeviceRow, !pickingDevice),
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

    // ── Status card and cooler panel ─────────────────────────────────────────

    private func refreshCards(connected: Bool) {
        statusCard.update(StatusCardView.ViewModel(
            dieTempC: thermal.dieTemperatureC,
            thermalState: thermal.thermalState,
            mode: ble.mode,
            isConnected: connected,
            appMode: appMode))

        coolerPanel.update(CoolerPanelView.ViewModel(
            isConnected: connected,
            phase: ble.phase,
            deviceModelName: ble.profile?.modelName,
            telemetry: telemetry,
            mode: ble.mode,
            fanTint: led.fanTint(dieC: thermal.dieTemperatureC),
            deviceLooksPoweredOff: switchMonitor.looksPoweredOff))
    }

}
