import AppKit

/// Inline device chooser embedded in the app's existing status menu.
///
/// A discovered device is never preselected: each result is its own button, so
/// connecting always requires a deliberate click even when only one supported
/// cooler is nearby.
final class DevicePickerView: NSView {

    var onSelect: ((CoolerBLEManager.DiscoveredDevice) -> Void)?
    var onScanAgain: (() -> Void)?

    private var devices: [CoolerBLEManager.DiscoveredDevice] = []
    private let statusLabel = NSTextField(labelWithString: Status.scanning)
    private let scrollView = NSScrollView()
    private let rowsView = FlippedView()
    private let scanButton = NSButton()

    private enum Layout {
        static let height: CGFloat = 142
        static let rowHeight: CGFloat = 30
        static let rowGap: CGFloat = 4
    }

    private enum Status {
        static let scanning = "Scanning for supported coolers…"
        static let none = "No supported coolers found"
        static func found(_ count: Int) -> String {
            "Choose a device to connect · \(count) found"
        }
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))
        autoresizingMask = .width

        let pad = UIStyle.hPad

        let header = NSTextField(labelWithString: "AVAILABLE DEVICES")
        header.font = UIStyle.sectionFont
        header.textColor = .tertiaryLabelColor
        header.frame = NSRect(x: pad, y: 8, width: width - pad * 2, height: 13)
        addSubview(header)

        statusLabel.font = UIStyle.captionFont
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: pad, y: 24, width: width - pad * 2, height: 16)
        addSubview(statusLabel)

        scrollView.frame = NSRect(x: pad, y: 43, width: width - pad * 2, height: 62)
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
        scanButton.frame = NSRect(x: pad, y: 110, width: 96, height: 24)
        scanButton.isEnabled = false
        addSubview(scanButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setScanning(_ scanning: Bool) {
        guard scanning else {
            statusLabel.stringValue = devices.isEmpty ? Status.none : Status.found(devices.count)
            scanButton.isEnabled = true
            return
        }

        devices = []
        rebuildRows()
        statusLabel.stringValue = Status.scanning
        scanButton.isEnabled = false
        scrollView.isHidden = true
    }

    /// Replaces the result buttons, strongest signal first. Nothing is chosen
    /// automatically; pressing one of these buttons is the selection action.
    func updateDevices(_ devices: [CoolerBLEManager.DiscoveredDevice]) {
        self.devices = devices.sorted { $0.rssi > $1.rssi }
        rebuildRows()
        statusLabel.stringValue = devices.isEmpty ? Status.none : Status.found(devices.count)
        scanButton.isEnabled = true
        scrollView.isHidden = devices.isEmpty
    }

    private func rebuildRows() {
        rowsView.subviews.forEach { $0.removeFromSuperview() }

        let width = max(scrollView.contentSize.width, 1)
        let stride = Layout.rowHeight + Layout.rowGap
        let contentHeight = max(scrollView.contentSize.height,
                                CGFloat(devices.count) * stride - Layout.rowGap)
        rowsView.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

        for (index, device) in devices.enumerated() {
            let title = "\(device.profile.modelName)  ·  \(Self.signalDescription(device.rssi))"
            let button = NSButton(title: title, target: self, action: #selector(deviceTapped(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.font = UIStyle.bodyFont
            button.alignment = .left
            button.frame = NSRect(x: 0, y: CGFloat(index) * stride,
                                  width: width, height: Layout.rowHeight)
            button.autoresizingMask = .width
            rowsView.addSubview(button)
        }
    }

    @objc private func deviceTapped(_ sender: NSButton) {
        guard devices.indices.contains(sender.tag) else { return }
        let menu = enclosingMenuItem?.menu
        onSelect?(devices[sender.tag])
        menu?.cancelTracking()
    }

    @objc private func scanAgainTapped() {
        setScanning(true)
        onScanAgain?()
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
