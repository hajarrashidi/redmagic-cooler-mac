import AppKit

/// The menu items whose visibility or title changes with state.
///
/// Grouped into a struct so `AppDelegate` carries one property instead of a
/// dozen implicitly-unwrapped optionals, and so `refresh()` reads as a list of
/// assignments against a named group rather than a wall of `itemFoo.isHidden`.
struct MenuRows {
    let updateBanner: NSMenuItem
    let skipUpdate: NSMenuItem
    let coolerPanel: NSMenuItem
    let devicePicker: NSMenuItem
    let modeSwitch: NSMenuItem
    let autoOptions: NSMenuItem
    let coolingSlider: NSMenuItem
    let manualTimer: NSMenuItem
    let effect: NSMenuItem
    let breathToggle: NSMenuItem
    let color: NSMenuItem
    let turnOff: NSMenuItem
    let changeDevice: NSMenuItem
}

extension AppDelegate: NSMenuDelegate {

    /// Builds the menu once at launch. It is never rebuilt — `refresh()` mutates
    /// the items in place, because rebuilding while the menu is open would
    /// dismiss it mid-interaction.
    func buildMenu() {
        let width = UIStyle.menuWidth
        menu = NSMenu()
        menu.delegate = self

        // ── Update notice ────────────────────────────────────────────────────
        // Above everything else: it's the one row about the app itself rather
        // than the cooler, and it only ever appears when there is news. All
        // three items hide together, so normally the menu opens on the card.
        updateBanner = BannerView(width: width)
        updateBanner.onClick = { [weak self] in self?.openReleasePage() }
        let updateBannerItem = wrap(updateBanner)
        updateBannerItem.isHidden = true
        menu.addItem(updateBannerItem)

        // A custom row rather than a plain item, so it paints the backdrop its
        // neighbours do — see `UIStyle.menuBackdrop`.
        skipUpdateRow = settingsRow("Skip This Version", symbol: "xmark") {
            [weak self] in self?.skipThisVersion()
        }
        let skipUpdate = wrap(skipUpdateRow)
        skipUpdate.isHidden = true
        menu.addItem(skipUpdate)

        // ── Status card ──────────────────────────────────────────────────────
        statusCard = StatusCardView(width: width)
        menu.addItem(wrap(statusCard))

        // The cooler's panel is a row of its own so it can step aside for the
        // picker: the two are alternatives, one always taking the other's
        // place, and Connect lives on the panel rather than as a menu item
        // below it.
        coolerPanel = CoolerPanelView(width: width)
        coolerPanel.onConnect = { [weak self] in self?.connectDevice() }
        let coolerPanelItem = wrap(coolerPanel)
        menu.addItem(coolerPanelItem)

        devicePicker = DevicePickerView(width: width)
        devicePicker.onSelect = { [weak self] in self?.selectDiscoveredDevice($0) }
        devicePicker.onScan = { [weak self] in self?.scanAgainForDevices() }
        devicePicker.onOpenGuide = { [weak self] in self?.openAddingDevicesGuide() }
        devicePicker.onRequestPermission = { [weak self] in self?.requestBluetoothAccess() }
        devicePicker.onOpenBluetoothSettings = {
            [weak self] in self?.openBluetoothSettings()
        }
        let devicePickerItem = wrap(devicePicker)
        devicePickerItem.isHidden = true
        menu.addItem(devicePickerItem)

        // ── Cooling ──────────────────────────────────────────────────────────
        // Shown only once the cooler connects; every control here is
        // meaningless — and misleading — without a live link.
        modeSwitch = ModeSwitchView(width: width)
        modeSwitch.onSelect = { [weak self] in self?.selectMode($0) }
        // The cooler section is one panel: mode on top, its active cooling
        // control next, followed by the visible LED controls.
        modeSwitch.panelSegment = .top
        let modeSwitchItem = wrap(modeSwitch)
        menu.addItem(modeSwitchItem)

        autoOptions = AutoOptionsView(width: width)
        autoOptions.onEngageChange = { [weak self] in self?.setEngage($0) }
        autoOptions.panelSegment = .bottom
        let autoOptionsItem = wrap(autoOptions)
        menu.addItem(autoOptionsItem)

        coolingSlider = CoolingSliderView(width: width)
        coolingSlider.onStep = { [weak self] in self?.applyManualStep($0) }
        coolingSlider.panelSegment = .bottom
        let coolingSliderItem = wrap(coolingSlider)
        menu.addItem(coolingSliderItem)

        // Directly under the level it limits, so the two read as one control:
        // how hard, and for how long.
        manualTimerRow = ManualTimerView(width: width)
        manualTimerRow.onSelect = { [weak self] in self?.setManualTimeout($0) }
        manualTimerRow.panelSegment = .bottom
        let manualTimerItem = wrap(manualTimerRow)
        menu.addItem(manualTimerItem)

        // LED controls are part of the same cooler-control panel as its mode.
        effectPicker = LedEffectPickerView(width: width)
        effectPicker.onSelect = { [weak self] in self?.applyLedEffect($0) }
        let effectItem = wrap(effectPicker)
        menu.addItem(effectItem)

        breathToggle = BreathStyleToggleView(width: width)
        breathToggle.onSelect = { [weak self] in self?.applyBreathStyle($0) }
        let breathToggleItem = wrap(breathToggle)
        menu.addItem(breathToggleItem)

        colorPicker = HueSpectrumPickerView(width: width)
        colorPicker.onSelect = { [weak self] in self?.applyLedHue($0) }
        let colorItem = wrap(colorPicker)
        menu.addItem(colorItem)

        // ── Settings ─────────────────────────────────────────────────────────
        // Custom rows rather than plain items, so the section can sit on a
        // panel like every other group. Which row opens and closes the panel
        // depends on what is visible, so refresh() assigns the segments.
        menu.addItem(wrap(SectionHeaderRow(width: width, title: "Settings")))

        turnOffRow = settingsRow("Turn Off", symbol: "power") {
            [weak self] in self?.turnOff()
        }
        let turnOff = wrap(turnOffRow)
        menu.addItem(turnOff)

        // Unlike its neighbours this row leaves the menu open, because
        // everything it does — the inline picker, the scan progress — is
        // displayed in the rows above it.
        changeDeviceRow = MenuActionRow(width: width, title: "Change Device…",
                                        symbol: "antenna.radiowaves.left.and.right")
        changeDeviceRow.onClick = { [weak self] in self?.changeDevice() }
        let changeDevice = wrap(changeDeviceRow)
        menu.addItem(changeDevice)

        // The way out of the app, and the last row for that reason. It replaces
        // a plain "Quit": quitting already turned the cooler off and dropped the
        // link — leaving hardware running after its controller exits is not an
        // option — so a separate Quit only offered the same thing under a name
        // that hid what it did.
        turnOffQuitRow = settingsRow("Turn Off & Quit", symbol: "power.circle") {
            [weak self] in self?.turnOffAndQuit()
        }
        let turnOffAndQuit = wrap(turnOffQuitRow)
        menu.addItem(turnOffAndQuit)

        // Breathing room under the last row, and the owner of the window's
        // bottom corners.
        menu.addItem(wrap(MenuFooterRow(width: width)))

        rows = MenuRows(updateBanner: updateBannerItem,
                        skipUpdate: skipUpdate,
                        coolerPanel: coolerPanelItem,
                        devicePicker: devicePickerItem,
                        modeSwitch: modeSwitchItem,
                        autoOptions: autoOptionsItem,
                        coolingSlider: coolingSliderItem,
                        manualTimer: manualTimerItem,
                        effect: effectItem,
                        breathToggle: breathToggleItem,
                        color: colorItem,
                        turnOff: turnOff,
                        changeDevice: changeDevice)

        statusItem.menu = menu
    }

    // ── NSMenuDelegate ───────────────────────────────────────────────────────

    /// Animate the fan only while the menu is actually visible.
    func menuWillOpen(_ menu: NSMenu) {
        coolerPanel.startAnimating()
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        coolerPanel.stopAnimating()
    }

    // ── Item factories ───────────────────────────────────────────────────────

    private func wrap(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func banner(_ width: CGFloat,
                        _ style: BannerView.Style,
                        _ text: String,
                        symbol: String,
                        spinner: Bool = false) -> BannerView {
        let view = BannerView(width: width)
        view.configure(style: style, text: text, symbol: symbol, showSpinner: spinner)
        return view
    }

    /// A settings-panel action row that closes the menu when clicked, the way
    /// the plain items it replaced did.
    private func settingsRow(_ title: String, symbol: String,
                             onClick: @escaping () -> Void) -> MenuActionRow {
        let row = MenuActionRow(width: UIStyle.menuWidth, title: title, symbol: symbol)
        row.dismissesMenu = true
        row.onClick = onClick
        return row
    }
}
