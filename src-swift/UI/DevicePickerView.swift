import AppKit

/// Inline device chooser embedded in the app's existing status menu.
///
/// It takes the cooler panel's place whenever there is no link to describe: at
/// first run, and whenever the user asks to change device. That is why it owns
/// the Scan button — with no remembered cooler, scanning is the only thing the
/// app can usefully offer, and it should be the thing the menu leads with.
///
/// A discovered device is never preselected: each supported result is its own
/// row, so connecting always requires a deliberate click even when only one
/// cooler is nearby.
///
/// Every result is listed, including devices the app has no profile for, which
/// appear greyed out and unclickable. That is the point rather than an
/// oversight — dropping them, as the app used to, left the owner of a newer
/// cooler staring at "no supported coolers found", unable to tell whether the
/// app had even seen their device. Showing the advertised name gives them step
/// one of the porting guide, which the footer links to.
final class DevicePickerView: PanelRowView {

    var onSelect: ((CoolerBLEManager.DiscoveredDevice) -> Void)?
    var onScan: (() -> Void)?
    var onOpenGuide: (() -> Void)?
    /// Brings the Bluetooth adapter up for the first time, which is what asks
    /// the user for permission.
    var onRequestPermission: (() -> Void)?
    var onOpenBluetoothSettings: (() -> Void)?

    private var devices: [CoolerBLEManager.DiscoveredDevice] = []
    /// The live Bluetooth phase, rather than a flag this view sets when the
    /// Scan button is pressed. Pressing Scan with the adapter off starts
    /// nothing at all, and a picker left spinning on that reports the app's own
    /// bug as the device's.
    private var phase: ConnectionPhase = .idle
    private var permission: CoolerBLEManager.Permission = .granted
    /// A scan has finished at least once, which is what separates "nothing
    /// found" from "nothing looked for yet".
    private var hasScanned = false

    private var isScanning: Bool { phase == .scanning }
    private var isBluetoothAvailable: Bool {
        permission == .granted && phase != .bluetoothOff
    }

    private let statusLabel = NSTextField(labelWithString: "")
    private let listSpinner = NSProgressIndicator()
    private let scrollView = NSScrollView()
    private let rowsView = FlippedView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let scanButton = PillButton(title: "Scan")
    private let guideLink = LinkButton(title: "Add support for your cooler →")

    /// The picker's own height never changes, and deliberately so: `NSMenu`
    /// re-lays out hidden and shown *rows* while it is open, but not a row
    /// whose view resizes under it — and results arrive mid-scan, with the menu
    /// wide open. So the result list is a fixed window that scrolls, and the
    /// empty states are drawn inside that window rather than collapsing it.
    private enum Layout {
        static let pad = UIStyle.panelPad
        static let headerHeight: CGFloat = 13
        static let statusHeight: CGFloat = 16
        static let listHeight: CGFloat = 138
        static let groupHeaderHeight: CGFloat = 18
        static let rowHeight: CGFloat = 26
        static let rowGap: CGFloat = 2
        static let spinnerSize: CGFloat = 18
    }

    private enum Text {
        static let scanning = "Scanning for coolers…"
        static let unscanned = "Scan to find coolers nearby"
        static let nothingFound = "No devices found"
        static let needsPermission = "Bluetooth access is needed to find your cooler"
        static let permissionDenied = "Bluetooth access was denied"

        static let unscannedHint = "Press Scan to look for nearby coolers"
        /// Complements the status line above rather than repeating it: that
        /// already says nothing was found, so this says what to do about it.
        static let nothingFoundHint = "Move the cooler closer, then scan again"
        static let bluetoothOffHint = "Turn Bluetooth on, then scan"
        static let needsPermissionHint = "macOS will ask you once"
        static let deniedHint = "Turn it back on in System Settings"

        static let scan = "Scan"
        static let allow = "Allow Bluetooth Access"
        static let openSettings = "Open Bluetooth Settings"
    }

    init(width: CGFloat) {
        let content = width - UIStyle.panelContentX * 2
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        autoresizingMask = .width
        // The picker is a section of its own, on the same surface as the rest.
        panelSegment = .only

        let pad = UIStyle.panelContentX
        var y = Layout.pad

        let header = UIStyle.sectionLabel("AVAILABLE DEVICES")
        header.frame = NSRect(x: pad, y: y, width: content, height: Layout.headerHeight)
        addSubview(header)
        y += Layout.headerHeight + 5

        statusLabel.font = UIStyle.captionFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: pad, y: y, width: content, height: Layout.statusHeight)
        addSubview(statusLabel)
        y += Layout.statusHeight + 6

        let listFrame = NSRect(x: pad, y: y, width: content, height: Layout.listHeight)
        scrollView.frame = listFrame
        scrollView.autoresizingMask = .width
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // A hairline overlay scroller. The legacy style reserves a 15pt gutter
        // out of a 260pt row and paints a track behind it, which in a list this
        // short reads as a second border down the panel.
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = ThinScroller()
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.documentView = rowsView
        addSubview(scrollView)

        // Both empty states are drawn inside the list window, which cannot
        // collapse — an unexplained hole is worse than either message.
        emptyLabel.font = UIStyle.captionFont
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: pad, y: y + (Layout.listHeight - 16) / 2,
                                  width: content, height: 16)
        addSubview(emptyLabel)

        listSpinner.style = .spinning
        listSpinner.controlSize = .small
        listSpinner.isDisplayedWhenStopped = false
        listSpinner.frame = NSRect(x: pad + (content - Layout.spinnerSize) / 2,
                                   y: y + (Layout.listHeight - Layout.spinnerSize) / 2,
                                   width: Layout.spinnerSize, height: Layout.spinnerSize)
        addSubview(listSpinner)
        y += Layout.listHeight + 8

        // Full panel width. It is the only action on this row, and often the
        // only one in the whole menu — sizing it to the word "Scan" made the
        // primary thing to do here the smallest thing on screen.
        scanButton.onClick = { [weak self] in self?.scanTapped() }
        scanButton.frame = NSRect(x: pad, y: y, width: content,
                                  height: PillButton.height)
        addSubview(scanButton)
        y += PillButton.height + 10

        guideLink.onClick = { [weak self] in self?.guideTapped() }
        // Sized to its text, so the underline appears under the cursor rather
        // than anywhere along a full-width invisible strip.
        guideLink.frame = NSRect(x: pad, y: y, width: min(guideLink.fittingWidth, content),
                                 height: LinkButton.height)
        addSubview(guideLink)
        y += LinkButton.height + Layout.pad

        frame.size.height = y
        applyState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // ── State ────────────────────────────────────────────────────────────────

    /// Takes the live connection phase, from the same one-a-second refresh that
    /// drives every other row. Everything the picker says about progress is
    /// derived from it, so a scan that never starts — or one ended by something
    /// other than the settle timer — can't leave the view stranded.
    func setState(phase: ConnectionPhase, permission: CoolerBLEManager.Permission) {
        guard phase != self.phase || permission != self.permission else { return }
        if phase == .scanning {
            // Results from the previous scan describe a moment that has passed;
            // a device now out of range must not stay clickable.
            devices = []
            rebuildRows()
        }
        self.phase = phase
        self.permission = permission
        applyState()
    }

    /// Replaces the result rows, strongest signal first within each group.
    /// Nothing is chosen automatically; clicking a supported row is the
    /// selection action.
    func updateDevices(_ devices: [CoolerBLEManager.DiscoveredDevice]) {
        self.devices = devices.sorted { $0.rssi > $1.rssi }
        hasScanned = true
        rebuildRows()
        applyState()
    }

    private func applyState() {
        statusLabel.stringValue = statusText

        // The button carries the whole permission story. Until Bluetooth has
        // been granted, "Scan" is a button that cannot work, and the app has no
        // way to explain that after the fact — so it offers the grant instead.
        switch permission {
        case .granted:  scanButton.title = Text.scan
        case .notAsked: scanButton.title = Text.allow
        case .denied:   scanButton.title = Text.openSettings
        }
        // Only a running scan disables it; the permission titles are the two
        // cases where pressing it is the entire point.
        scanButton.isEnabled = !isScanning && (permission != .granted || phase != .bluetoothOff)

        let hasRows = !visibleGroups.isEmpty
        scrollView.isHidden = !hasRows

        if isScanning {
            listSpinner.startAnimation(nil)
        } else {
            listSpinner.stopAnimation(nil)
        }

        if let hint = emptyHint, !hasRows {
            emptyLabel.stringValue = hint
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private var statusText: String {
        // Permission outranks everything: without it there is no list to
        // describe, only a thing to ask for.
        switch permission {
        case .notAsked: return Text.needsPermission
        case .denied:   return Text.permissionDenied
        case .granted:  break
        }
        // "Bluetooth is off" outranks anything about the results: with the
        // adapter down, the list is stale rather than empty.
        guard isBluetoothAvailable else { return phase.statusText }
        if isScanning { return Text.scanning }
        guard hasScanned else { return Text.unscanned }
        let supported = devices.filter(\.isSupported).count
        if supported > 0 {
            return "Choose a cooler to connect · \(supported) supported"
        }
        if devices.isEmpty { return Text.nothingFound }
        return "No supported coolers · \(devices.count) other "
             + (devices.count == 1 ? "device" : "devices")
    }

    /// What to say in the empty list window. `nil` while scanning — the spinner
    /// sitting there says it better than a sentence would.
    ///
    /// The Bluetooth cases name the fix rather than restating the problem: this
    /// is the one screen where the user is stuck, and "Bluetooth is off" is
    /// already on the line above.
    private var emptyHint: String? {
        switch permission {
        case .notAsked: return Text.needsPermissionHint
        case .denied:   return Text.deniedHint
        case .granted:  break
        }
        switch phase {
        case .scanning:              return nil
        case .bluetoothOff:          return Text.bluetoothOffHint
        default:
            return hasScanned ? Text.nothingFoundHint : Text.unscannedHint
        }
    }

    /// The groups to render, in order.
    ///
    /// Everything in range is listed. This used to hide unrelated devices
    /// behind a "Show all devices" checkbox, which asked the user to make a
    /// decision about a list they could not yet see — and in an app whose whole
    /// job is to find one cooler, scrolling a handful of extra rows costs less
    /// than the checkbox did.
    private var visibleGroups: [(title: String, devices: [CoolerBLEManager.DiscoveredDevice])] {
        let groups: [(String, [CoolerBLEManager.DiscoveredDevice])] = [
            ("SUPPORTED", devices.filter(\.isSupported)),
            ("NOT SUPPORTED YET", devices.filter {
                if case .unsupported = $0.support { return true }
                return false
            }),
            ("OTHER NEARBY DEVICES", devices.filter {
                if case .other = $0.support { return true }
                return false
            }),
        ]
        return groups.filter { !$0.1.isEmpty }.map { (title: $0.0, devices: $0.1) }
    }

    // ── Rows ─────────────────────────────────────────────────────────────────

    private func rebuildRows() {
        rowsView.subviews.forEach { $0.removeFromSuperview() }

        let width = max(scrollView.contentSize.width, 1)
        var laidOut: [(NSView, CGFloat)] = []
        var y: CGFloat = 0

        for group in visibleGroups {
            let header = UIStyle.sectionLabel(group.title)
            laidOut.append((header, Layout.groupHeaderHeight))
            y += Layout.groupHeaderHeight

            for device in group.devices {
                let row = DeviceRowView(device: device)
                // Unsupported rows are shown for identification only — there is
                // no profile to drive them with.
                if device.isSupported {
                    row.onClick = { [weak self] in self?.deviceTapped(device) }
                }
                laidOut.append((row, Layout.rowHeight))
                y += Layout.rowHeight + Layout.rowGap
            }
        }

        let contentHeight = max(scrollView.contentSize.height, y)
        rowsView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

        var cursor: CGFloat = 0
        for (view, height) in laidOut {
            view.frame = NSRect(x: 0, y: cursor, width: width, height: height)
            view.autoresizingMask = .width
            rowsView.addSubview(view)
            cursor += height + (view is DeviceRowView ? Layout.rowGap : 0)
        }
    }

    // ── Mouse ────────────────────────────────────────────────────────────────
    //
    // `NSMenu` tracks the mouse itself and delivers events to the *item's*
    // view — this one. Nothing nested inside it ever gets `mouseEntered`, so
    // the buttons, the link and the result rows had tracking areas that could
    // never fire. This view owns the pointer for the whole row and hands both
    // hover and clicks down to whatever is under it.

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            // .activeAlways, not .activeInActiveApp: this is a menu-bar app
            // that never becomes the active application just because its menu
            // is open.
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(at: nil)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if scanButton.frame.contains(point) {
            scanButton.performClick()
        } else if guideLink.frame.contains(point) {
            guideLink.performClick()
        } else if let row = deviceRow(at: point) {
            row.performClick()
        }
    }

    private func updateHover(at point: NSPoint?) {
        scanButton.isHovered = point.map(scanButton.frame.contains) ?? false
        guideLink.isHovered = point.map(guideLink.frame.contains) ?? false
        let hovered = point.flatMap(deviceRow(at:))
        for case let row as DeviceRowView in rowsView.subviews {
            row.isHovered = (row === hovered)
        }
    }

    /// The result row under a point in this view's coordinates, if the point is
    /// inside the list window at all — a row scrolled out of sight still has a
    /// frame, and without the clip test the hover would follow it off-screen.
    private func deviceRow(at point: NSPoint) -> DeviceRowView? {
        guard !scrollView.isHidden, scrollView.frame.contains(point) else { return nil }
        let inRows = rowsView.convert(point, from: self)
        return rowsView.subviews.first {
            $0 is DeviceRowView && $0.frame.contains(inRows)
        } as? DeviceRowView
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    private func deviceTapped(_ device: CoolerBLEManager.DiscoveredDevice) {
        guard device.isSupported else { return }
        let menu = enclosingMenuItem?.menu
        onSelect?(device)
        menu?.cancelTracking()
    }

    /// No optimistic state change: starting the scan moves the phase to
    /// `.scanning` and the refresh that follows brings the whole row with it,
    /// which is also the only version of this that copes with the scan not
    /// starting at all.
    private func scanTapped() {
        switch permission {
        case .granted:
            onScan?()
        case .notAsked:
            onRequestPermission?()
        case .denied:
            // Only System Settings can reverse a denial, so this is the one
            // button here that has to leave the menu.
            let menu = enclosingMenuItem?.menu
            onOpenBluetoothSettings?()
            menu?.cancelTracking()
        }
    }

    private func guideTapped() {
        let menu = enclosingMenuItem?.menu
        onOpenGuide?()
        menu?.cancelTracking()
    }
}

/// One discovered device: its advertised name, and either its signal strength
/// or why it can't be connected to.
private final class DeviceRowView: NSView {

    /// Left unset for a device the app has no profile for, which both greys the
    /// row out and makes it ignore the cursor.
    var onClick: (() -> Void)? {
        didSet { applyTint() }
    }

    /// Set by the picker, which owns the mouse for the whole row.
    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    private static let detailWidth: CGFloat = 84

    init(device: CoolerBLEManager.DiscoveredDevice) {
        super.init(frame: .zero)

        nameLabel.stringValue = device.name
        nameLabel.font = UIStyle.bodyFont
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        detailLabel.stringValue = device.isSupported
            ? Self.signalDescription(device.rssi)
            : "Not supported"
        detailLabel.font = UIStyle.captionFont
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.alignment = .right
        addSubview(detailLabel)

        applyTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset: CGFloat = 6
        let detail = Self.detailWidth
        nameLabel.frame = NSRect(x: inset + 6, y: (newSize.height - 15) / 2,
                                 width: max(newSize.width - detail - inset * 2 - 12, 1),
                                 height: 15)
        detailLabel.frame = NSRect(x: newSize.width - inset - 6 - detail,
                                   y: (newSize.height - 14) / 2,
                                   width: detail, height: 14)
    }

    private func applyTint() {
        nameLabel.textColor = (onClick == nil) ? .tertiaryLabelColor : .labelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered, onClick != nil else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 0),
                     xRadius: 5, yRadius: 5).fill()
    }

    /// Called by the picker once it has decided the click landed here.
    func performClick() {
        onClick?()
    }

    /// See `PillButton.mouseUp` — whichever of the two runs, only one does.
    override func mouseUp(with event: NSEvent) {
        performClick()
    }

    private static func signalDescription(_ rssi: Int) -> String {
        switch rssi {
        case (-50)...:      return "Excellent"
        case (-70)..<(-50): return "Good"
        case (-85)..<(-70): return "Fair"
        default:            return "Weak"
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A hairline overlay scroller.
///
/// `NSScroller` at `.mini` is still 11pt of track and knob, which in a 138pt
/// list reads as a second border down the panel. This is the same scroller with
/// its width and its knob cut down to the width of a caret.
private final class ThinScroller: NSScroller {

    private static let width: CGFloat = 5
    private static let knobInset: CGFloat = 1

    override class func scrollerWidth(for controlSize: NSControl.ControlSize,
                                      scrollerStyle: NSScroller.Style) -> CGFloat {
        width
    }

    /// Nothing behind the knob. An overlay scroller's slot is already faint;
    /// at this width it only muddies the edge of the list.
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let rect = rect(for: .knob).insetBy(dx: Self.knobInset, dy: Self.knobInset)
        let radius = rect.width / 2
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
}
