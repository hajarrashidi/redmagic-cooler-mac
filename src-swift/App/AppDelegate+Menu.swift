import AppKit

/// The menu items whose visibility or title changes with state.
///
/// Grouped into a struct so `AppDelegate` carries one property instead of a
/// dozen implicitly-unwrapped optionals, and so `refresh()` reads as a list of
/// assignments against a named group rather than a wall of `itemFoo.isHidden`.
struct MenuRows {
    let updateBanner: NSMenuItem
    let skipUpdate: NSMenuItem
    let updateSeparator: NSMenuItem
    let connect: NSMenuItem
    let devicePicker: NSMenuItem
    let modeSwitch: NSMenuItem
    let autoOptions: NSMenuItem
    let coolingSlider: NSMenuItem
    let manualWarning: NSMenuItem
    let switchingBanner: NSMenuItem
    let deviceOffBanner: NSMenuItem
    let ledSeparator: NSMenuItem
    let effect: NSMenuItem
    let breathToggle: NSMenuItem
    let color: NSMenuItem
    let ledOffBanner: NSMenuItem
    let turnOff: NSMenuItem
    let turnOffAndDisconnect: NSMenuItem
    let startAtLogin: NSMenuItem
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

        let skipUpdate = actionItem("Skip This Version", #selector(skipThisVersion))
        skipUpdate.isHidden = true
        menu.addItem(skipUpdate)

        let updateSeparator = NSMenuItem.separator()
        updateSeparator.isHidden = true
        menu.addItem(updateSeparator)

        // ── Status card ──────────────────────────────────────────────────────
        statusCard = StatusCardView(width: width)
        menu.addItem(wrap(statusCard))
        menu.addItem(.separator())

        // ── Connection / cooling ─────────────────────────────────────────────
        // Shown only until the cooler connects; every control below it is
        // meaningless — and misleading — without a live link.
        let connect = actionItem("Connect", #selector(connectDevice),
                                 symbol: "antenna.radiowaves.left.and.right")
        menu.addItem(connect)

        devicePicker = DevicePickerView(width: width)
        devicePicker.onSelect = { [weak self] in self?.selectDiscoveredDevice($0) }
        devicePicker.onScanAgain = { [weak self] in self?.scanAgainForDevices() }
        devicePicker.onOpenGuide = { [weak self] in self?.openAddingDevicesGuide() }
        let devicePickerItem = wrap(devicePicker)
        devicePickerItem.isHidden = true
        menu.addItem(devicePickerItem)

        modeSwitch = ModeSwitchView(width: width)
        modeSwitch.onSelect = { [weak self] in self?.selectMode($0) }
        // The cooling section is one panel: the mode switch on top, and exactly
        // one of the auto options or the slider closing it (refresh shows one
        // or the other, never both).
        modeSwitch.panelSegment = .top
        let modeSwitchItem = wrap(modeSwitch)
        menu.addItem(modeSwitchItem)

        autoOptions = AutoOptionsView(width: width)
        autoOptions.onProfile = { [weak self] in self?.selectAutoProfile($0) }
        autoOptions.onEngageChange = { [weak self] in self?.setCustomEngage($0) }
        autoOptions.panelSegment = .bottom
        let autoOptionsItem = wrap(autoOptions)
        menu.addItem(autoOptionsItem)

        coolingSlider = CoolingSliderView(width: width)
        coolingSlider.onStep = { [weak self] in self?.applyManualStep($0) }
        coolingSlider.panelSegment = .bottom
        let coolingSliderItem = wrap(coolingSlider)
        menu.addItem(coolingSliderItem)

        let manualWarning = wrap(banner(width, .warning,
                                        "Manual stays on until you turn it off",
                                        symbol: "exclamationmark.triangle.fill"))
        menu.addItem(manualWarning)

        let switchingBanner = wrap(banner(width, .info, "Switching… please wait",
                                          symbol: "arrow.triangle.2.circlepath",
                                          spinner: true))
        menu.addItem(switchingBanner)

        // The app can command this cooler over Bluetooth but cannot override
        // its physical switch, so when that switch is off every control in the
        // menu silently does nothing. Say so rather than let the user conclude
        // the app is broken.
        let deviceOffBanner = wrap(banner(width, .warning,
                                          "Cooler's power switch is off",
                                          symbol: "power.circle.fill"))
        menu.addItem(deviceOffBanner)

        // ── LED ──────────────────────────────────────────────────────────────
        let ledSeparator = NSMenuItem.separator()
        menu.addItem(ledSeparator)

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

        // Replaces the LED controls while the cooler is off — its LED cannot
        // show a colour when it isn't running.
        let ledOffBanner = wrap(banner(width, .neutral,
                                       "Cooler is off · turn on to set LED",
                                       symbol: "powersleep"))
        menu.addItem(ledOffBanner)

        // ── Settings ─────────────────────────────────────────────────────────
        // Custom rows rather than plain items, so the section can sit on a
        // panel like every other group. Which row opens and closes the panel
        // depends on what is visible, so refresh() assigns the segments.
        menu.addItem(.separator())
        menu.addItem(sectionHeader("Settings"))

        turnOffRow = settingsRow("Turn Off", symbol: "power") {
            [weak self] in self?.turnOff()
        }
        let turnOff = wrap(turnOffRow)
        menu.addItem(turnOff)

        turnOffDisconnectRow = settingsRow("Turn Off & Disconnect Bluetooth",
                                           symbol: "antenna.radiowaves.left.and.right.slash") {
            [weak self] in self?.turnOffAndDisconnect()
        }
        let turnOffAndDisconnect = wrap(turnOffDisconnectRow)
        menu.addItem(turnOffAndDisconnect)

        startAtLoginRow = settingsRow("Start at Login",
                                      symbol: "arrow.right.to.line.compact") {
            [weak self] in self?.toggleStartAtLogin()
        }
        let startAtLogin = wrap(startAtLoginRow)
        menu.addItem(startAtLogin)

        // Unlike its neighbours this row leaves the menu open, because
        // everything it does — the inline picker, the scan progress — is
        // displayed in the rows above it.
        changeDeviceRow = MenuActionRow(width: width, title: "Change Device…",
                                        symbol: "antenna.radiowaves.left.and.right")
        changeDeviceRow.onClick = { [weak self] in self?.changeDevice() }
        let changeDevice = wrap(changeDeviceRow)
        menu.addItem(changeDevice)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit RedMagic Cooler", #selector(quitApp),
                                symbol: "xmark.circle"))

        rows = MenuRows(updateBanner: updateBannerItem,
                        skipUpdate: skipUpdate,
                        updateSeparator: updateSeparator,
                        connect: connect,
                        devicePicker: devicePickerItem,
                        modeSwitch: modeSwitchItem,
                        autoOptions: autoOptionsItem,
                        coolingSlider: coolingSliderItem,
                        manualWarning: manualWarning,
                        switchingBanner: switchingBanner,
                        deviceOffBanner: deviceOffBanner,
                        ledSeparator: ledSeparator,
                        effect: effectItem,
                        breathToggle: breathToggleItem,
                        color: colorItem,
                        ledOffBanner: ledOffBanner,
                        turnOff: turnOff,
                        turnOffAndDisconnect: turnOffAndDisconnect,
                        startAtLogin: startAtLogin,
                        changeDevice: changeDevice)

        statusItem.menu = menu
    }

    // ── NSMenuDelegate ───────────────────────────────────────────────────────

    /// Animate the fan only while the menu is actually visible.
    func menuWillOpen(_ menu: NSMenu) {
        statusCard.startAnimating()
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusCard.stopAnimating()
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

    private func actionItem(_ title: String,
                            _ selector: Selector,
                            symbol name: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.image = name.flatMap(symbolImage)
        return item
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        return image
    }

    /// A disabled, small-caps label used to title a group of items.
    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 0.6,
        ])
        return item
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
