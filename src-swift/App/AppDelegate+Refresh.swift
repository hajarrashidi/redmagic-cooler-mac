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
        refreshSettingsItems(coolerOn: coolerOn, pickingDevice: pickingDevice)
        refreshStatusItemButton()
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

        // Whichever row is first owns the window's top corners — see
        // `UIStyle.menuBackdrop`. The banner takes that job on the rare
        // occasions it appears, and hands it back to the card afterwards.
        let bannerLeads = (update != nil)
        updateBanner.menuEdges = bannerLeads ? .top : []
        statusCard.menuEdges = bannerLeads ? [] : .top

        guard let update else { return }
        switch installer.state {
        case .idle:
            updateBanner.configure(style: .info,
                                   text: "Version \(update.displayVersion) — install now",
                                   symbol: "arrow.down.circle.fill",
                                   showSpinner: false)
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
        }
    }

    // ── Control values ───────────────────────────────────────────────────────

    private func refreshControls(isManual: Bool) {
        // An install swaps the running app out from under itself and relaunches
        // it. Nothing else should be commanding the cooler while that happens,
        // so every control goes flat until it lands or fails.
        let enabled = !isSwitching && !isInstallingUpdate

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

        manualTimerRow.setTimeout(manualTimer.timeout)
        manualTimerRow.setRemaining(manualTimer.remainingText())
        manualTimerRow.setEnabled(enabled)

        // The picker narrates discovery entirely from these two, so it stays
        // truthful about scans that end without a result — including ones that
        // never start, because the adapter is off or was never allowed.
        devicePicker.setState(phase: ble.phase, permission: ble.permission,
                              actionsEnabled: !isInstallingUpdate)

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
        rows.devicesHeader.isHidden = !pickingDevice
        rows.coolerPanel.isHidden = pickingDevice

        rows.coolingHeader.isHidden = !connected
        rows.modeSwitch.isHidden = !connected
        rows.autoOptions.isHidden = !connected || isManual
        rows.coolingSlider.isHidden = !connected || !isManual
        // The auto-off limit belongs to Manual, and only Manual: Auto stands
        // itself down as the Mac cools, so it has nothing to time out.
        rows.manualTimer.isHidden = !connected || !isManual
        // LED controls only mean something while the cooler is running — its
        // LED cannot show a colour when it isn't.
        rows.ledHeader.isHidden = !coolerOn
        rows.effect.isHidden = !coolerOn
        rows.breathToggle.isHidden = !coolerOn || led.effect != .breath
        rows.color.isHidden = !coolerOn || !led.usesPickedColor

        // Cooling and Light are separate panels now that each has a title of
        // its own above it. Membership within each follows the active mode and
        // effect, so recompute both sets of corners.
        applyPanelSegments(to: [
            (modeSwitch, !rows.modeSwitch.isHidden),
            (autoOptions, !rows.autoOptions.isHidden),
            (coolingSlider, !rows.coolingSlider.isHidden),
            (manualTimerRow, !rows.manualTimer.isHidden),
        ])
        applyPanelSegments(to: [
            (effectPicker, !rows.effect.isHidden),
            (breathToggle, !rows.breathToggle.isHidden),
            (colorPicker, !rows.color.isHidden),
        ])

        // "Turn Off" only while it's running. "Turn Off & Quit" always: it is
        // the way out of the app, so it can never be the row that isn't there.
        rows.turnOff.isHidden = !coolerOn

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

    private func refreshSettingsItems(coolerOn: Bool, pickingDevice: Bool) {
        for row in [turnOffRow, changeDeviceRow, turnOffQuitRow] {
            row?.isEnabled = !isInstallingUpdate
        }

        // Mirrors the isHidden decisions made for these rows elsewhere in this
        // file, so the panel's corners always land on the rows actually shown.
        applyPanelSegments(to: [
            (turnOffRow, coolerOn),
            (changeDeviceRow, !pickingDevice),
            (turnOffQuitRow, true),
        ])
    }

    // ── Menu-bar button ──────────────────────────────────────────────────────

    private func refreshStatusItemButton() {
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
        // Always plain white. It used to be heat-graded while the cooler ran
        // and dimmed while it didn't, which put three states into a 16pt mark
        // sitting among two dozen monochrome system icons — read as a glitch
        // far more often than as a reading. The menu says all of it in words.
        let markColor = NSColor.white

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
            thermalState: thermal.thermalState))

        coolerPanel.update(CoolerPanelView.ViewModel(
            isConnected: connected,
            phase: ble.phase,
            deviceModelName: ble.profile?.modelName,
            telemetry: telemetry,
            mode: ble.mode,
            deviceLooksPoweredOff: switchMonitor.looksPoweredOff,
            note: coolerNote(connected: connected),
            actionsEnabled: !isInstallingUpdate))
    }

    /// The single thing the cooler panel says beyond its numbers, chosen in
    /// priority order.
    ///
    /// These were four banner rows that decided independently whether to
    /// appear, and the decisions had to be kept from contradicting each
    /// other — the manual reminder suppressed while switching, and again while
    /// the device's own switch was off, because two stacked warnings bury the
    /// one that explains what the user is actually seeing. As a single choice
    /// that can't happen: the most urgent fact wins, and the rest wait.
    private func coolerNote(connected: Bool) -> CoolerPanelView.Note? {
        guard connected else { return nil }
        if isSwitching { return .switching }
        if switchMonitor.looksPoweredOff { return .powerSwitchOff }
        if appMode == .manual {
            guard ble.mode.isOn else {
                // Off, and the user didn't do it — say who did.
                return manualTimedOut ? .manualTimedOut : nil
            }
            // "Stays on" is the honest line only when nothing else will end the
            // session. With a limit running, the countdown beside the picker
            // already says when it ends, and this would contradict it.
            return manualTimer.deadline == nil ? .manualStaysOn : nil
        }
        // Auto below its threshold: doing nothing, on purpose.
        return ble.mode.isOn ? nil : .autoWaiting(engageC: Int(autopilot.engageC))
    }

}
