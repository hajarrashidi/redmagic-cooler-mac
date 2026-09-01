import AppKit

/// Inline device chooser embedded in the app's existing status menu.
///
/// A discovered device is never preselected: each supported result is its own
/// button, so connecting always requires a deliberate click even when only one
/// cooler is nearby.
///
/// Devices the app has no profile for are listed too, greyed out and
/// unclickable. That is the point rather than an oversight — dropping them, as
/// the app used to, left the owner of a newer cooler staring at "no supported
/// coolers found", unable to tell whether the app had even seen their device.
/// Showing the advertised name gives them step one of the porting guide, which
/// the footer links to.
final class DevicePickerView: PanelRowView {

    var onSelect: ((CoolerBLEManager.DiscoveredDevice) -> Void)?
    var onScanAgain: (() -> Void)?
    var onOpenGuide: (() -> Void)?

    private var devices: [CoolerBLEManager.DiscoveredDevice] = []
    private var showsUnrelated = false

    private let statusLabel = NSTextField(labelWithString: Status.scanning)
    private let scrollView = NSScrollView()
    private let rowsView = FlippedView()
    private let scanButton = NSButton()
    private let showAllToggle = NSButton()
    private let guideButton = NSButton()

    private enum Layout {
        static let height: CGFloat = 196
        static let rowHeight: CGFloat = 30
        static let headerHeight: CGFloat = 18
        static let rowGap: CGFloat = 4
    }

    private enum Status {
        static let scanning = "Scanning for coolers…"
        static let none = "No coolers found nearby"
        static func found(supported: Int, unsupported: Int) -> String {
            if supported > 0 {
                return "Choose a device to connect · \(supported) supported"
            }
            if unsupported > 0 {
                return "No supported coolers · \(unsupported) unrecognised"
            }
            return none
        }
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))
        autoresizingMask = .width
        // The picker is a section of its own, on the same surface as the rest.
        panelSegment = .only

        let pad = UIStyle.panelContentX
        let content = width - pad * 2

        let header = UIStyle.sectionLabel("AVAILABLE DEVICES")
        header.frame = NSRect(x: pad, y: 8, width: content, height: 13)
        addSubview(header)

        statusLabel.font = UIStyle.captionFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: pad, y: 24, width: content, height: 16)
        addSubview(statusLabel)

        scrollView.frame = NSRect(x: pad, y: 43, width: content, height: 84)
        scrollView.autoresizingMask = .width
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = rowsView
        scrollView.isHidden = true
        addSubview(scrollView)

        scanButton.title = "Scan Again"
        scanButton.target = self
        scanButton.action = #selector(scanAgainTapped)
        scanButton.bezelStyle = .rounded
        scanButton.font = UIStyle.bodyFont
        scanButton.frame = NSRect(x: pad, y: 132, width: 96, height: 24)
        scanButton.isEnabled = false
        addSubview(scanButton)

        // Lets someone whose cooler advertises an unexpected name find it at
        // all — without it, an unrecognised model is invisible and unreportable.
        showAllToggle.title = "Show all devices"
        showAllToggle.setButtonType(.switch)
        showAllToggle.target = self
        showAllToggle.action = #selector(showAllToggled)
        showAllToggle.font = UIStyle.captionFont
        showAllToggle.frame = NSRect(x: pad + 104, y: 136, width: content - 104, height: 18)
        addSubview(showAllToggle)

        guideButton.title = "Own an unsupported cooler? Help add it →"
        guideButton.target = self
        guideButton.action = #selector(guideTapped)
        guideButton.bezelStyle = .inline
        guideButton.isBordered = false
        guideButton.font = UIStyle.captionFont
        guideButton.contentTintColor = .linkColor
        guideButton.alignment = .left
        guideButton.frame = NSRect(x: pad - 2, y: 164, width: content, height: 18)
        addSubview(guideButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // ── State ────────────────────────────────────────────────────────────────

    func setScanning(_ scanning: Bool) {
        guard scanning else {
            statusLabel.stringValue = Status.found(supported: counts.supported,
                                                   unsupported: counts.unsupported)
            scanButton.isEnabled = true
            return
        }

        devices = []
        rebuildRows()
        statusLabel.stringValue = Status.scanning
        scanButton.isEnabled = false
        scrollView.isHidden = true
    }

    /// Replaces the result rows, strongest signal first within each group.
    /// Nothing is chosen automatically; clicking a supported row is the
    /// selection action.
    func updateDevices(_ devices: [CoolerBLEManager.DiscoveredDevice]) {
        self.devices = devices.sorted { $0.rssi > $1.rssi }
        rebuildRows()
        statusLabel.stringValue = Status.found(supported: counts.supported,
                                               unsupported: counts.unsupported)
        scanButton.isEnabled = true
        scrollView.isHidden = visibleGroups.allSatisfy { $0.devices.isEmpty }
    }

    private var counts: (supported: Int, unsupported: Int) {
        var supported = 0
        var unsupported = 0
        for device in devices {
            switch device.support {
            case .supported: supported += 1
            case .unsupported: unsupported += 1
            case .other: break
            }
        }
        return (supported, unsupported)
    }

    /// The groups to render, in order. "Other devices" only appears once the
    /// user asks for it, so the common case stays a short, readable list.
    private var visibleGroups: [(title: String, devices: [CoolerBLEManager.DiscoveredDevice])] {
        var groups: [(String, [CoolerBLEManager.DiscoveredDevice])] = [
            ("SUPPORTED", devices.filter { $0.isSupported }),
            ("NOT SUPPORTED YET", devices.filter {
                if case .unsupported = $0.support { return true }
                return false
            }),
        ]
        if showsUnrelated {
            groups.append(("OTHER NEARBY DEVICES", devices.filter {
                if case .other = $0.support { return true }
                return false
            }))
        }
        return groups.filter { !$0.1.isEmpty }.map { (title: $0.0, devices: $0.1) }
    }

    // ── Rows ─────────────────────────────────────────────────────────────────

    private func rebuildRows() {
        rowsView.subviews.forEach { $0.removeFromSuperview() }

        let width = max(scrollView.contentSize.width, 1)
        let groups = visibleGroups

        var y: CGFloat = 0
        var laidOut: [(NSView, CGFloat)] = []

        for group in groups {
            let header = UIStyle.sectionLabel(group.title)
            laidOut.append((header, Layout.headerHeight))
            y += Layout.headerHeight

            for device in group.devices {
                let title = "\(device.name)  ·  \(Self.signalDescription(device.rssi))"
                let button = NSButton(title: title, target: self,
                                      action: #selector(deviceTapped(_:)))
                // The index is into `devices`, not the group, so the action can
                // look the device up without reconstructing the grouping.
                button.tag = devices.firstIndex {
                    $0.peripheral.identifier == device.peripheral.identifier
                } ?? -1
                button.bezelStyle = .rounded
                button.font = UIStyle.bodyFont
                button.alignment = .left
                // Unsupported rows are shown for identification only — there is
                // no profile to drive them with.
                button.isEnabled = device.isSupported
                laidOut.append((button, Layout.rowHeight))
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
            cursor += height + (view is NSButton ? Layout.rowGap : 0)
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    @objc private func deviceTapped(_ sender: NSButton) {
        guard devices.indices.contains(sender.tag) else { return }
        let device = devices[sender.tag]
        guard device.isSupported else { return }
        let menu = enclosingMenuItem?.menu
        onSelect?(device)
        menu?.cancelTracking()
    }

    @objc private func scanAgainTapped() {
        setScanning(true)
        onScanAgain?()
    }

    @objc private func showAllToggled() {
        showsUnrelated = (showAllToggle.state == .on)
        rebuildRows()
        scrollView.isHidden = visibleGroups.allSatisfy { $0.devices.isEmpty }
    }

    @objc private func guideTapped() {
        let menu = enclosingMenuItem?.menu
        onOpenGuide?()
        menu?.cancelTracking()
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
