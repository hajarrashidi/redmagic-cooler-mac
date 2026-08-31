import AppKit
import CoreBluetooth

/// The window shown when the cooler must be chosen by hand — on first launch,
/// or via "Change Device".
///
/// Consumes `CoolerBLEManager.DiscoveredDevice` directly rather than declaring
/// its own device type; the parallel struct that used to live here bought
/// nothing but a mapping step at every call site.
final class DevicePickerWindowController: NSWindowController {

    /// The user picked a device and hit Connect.
    var onSelect: ((CoolerBLEManager.DiscoveredDevice) -> Void)?
    /// The user asked to start discovery over.
    var onScanAgain: (() -> Void)?

    private var devices: [CoolerBLEManager.DiscoveredDevice] = []

    private var tableView: NSTableView!
    private var statusLabel: NSTextField!
    private var connectButton: NSButton!
    private var scanButton: NSButton!

    // ── Layout ───────────────────────────────────────────────────────────────

    private enum Layout {
        static let width: CGFloat = 340
        static let height: CGFloat = 260
        static let pad: CGFloat = 16
        static let buttonHeight: CGFloat = 28
        static let rowHeight: CGFloat = 34
        /// Where the signal-strength column starts within a row.
        static let signalColumnX: CGFloat = 200
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Connect to REDMAGIC Cooler"
        // The app keeps this controller alive to reuse it, so the window must
        // survive being closed.
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let (w, h, pad) = (Layout.width, Layout.height, Layout.pad)

        let logo = RedMagicLogoView(frame: NSRect(x: pad, y: h - pad - 24, width: 24, height: 24))
        content.addSubview(logo)

        let title = NSTextField(labelWithString: "REDMAGIC Cooler")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: pad + 32, y: h - pad - 22, width: w - pad * 2 - 32, height: 20)
        content.addSubview(title)

        statusLabel = NSTextField(labelWithString: Status.scanning)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: pad, y: h - pad - 46, width: w - pad * 2, height: 18)
        content.addSubview(statusLabel)

        let scrollFrame = NSRect(x: pad, y: 52, width: w - pad * 2, height: 130)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Layout.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(connectTapped)

        let column = NSTableColumn(identifier: .init("Device"))
        column.width = scrollFrame.width - 4
        tableView.addTableColumn(column)
        scrollView.documentView = tableView
        content.addSubview(scrollView)

        let cancel = button("Cancel", #selector(cancelTapped),
                            x: pad, width: 80)
        content.addSubview(cancel)

        scanButton = button("Scan Again", #selector(scanAgainTapped),
                            x: pad + 88, width: 100)
        scanButton.isEnabled = false
        content.addSubview(scanButton)

        connectButton = button("Connect", #selector(connectTapped),
                               x: w - pad - 100, width: 100)
        connectButton.isEnabled = false
        connectButton.keyEquivalent = "\r" // default button
        content.addSubview(connectButton)
    }

    private func button(_ title: String, _ action: Selector,
                        x: CGFloat, width: CGFloat) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: x, y: Layout.pad, width: width, height: Layout.buttonHeight)
        return button
    }

    // ── State ────────────────────────────────────────────────────────────────

    private enum Status {
        static let scanning = "Scanning for devices…"
        static let none = "No devices found"
        static func found(_ count: Int) -> String {
            "\(count) device\(count == 1 ? "" : "s") found"
        }
    }

    func setScanning(_ scanning: Bool) {
        statusLabel.stringValue = scanning ? Status.scanning : Status.found(devices.count)
        scanButton.isEnabled = !scanning
    }

    /// Replaces the device list, strongest signal first.
    func updateDevices(_ devices: [CoolerBLEManager.DiscoveredDevice]) {
        self.devices = devices.sorted { $0.rssi > $1.rssi }
        tableView.reloadData()
        statusLabel.stringValue = devices.isEmpty ? Status.none : Status.found(devices.count)
        scanButton.isEnabled = true
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    @objc private func connectTapped() {
        guard devices.indices.contains(tableView.selectedRow) else { return }
        onSelect?(devices[tableView.selectedRow])
        close()
    }

    @objc private func scanAgainTapped() {
        devices = []
        tableView.reloadData()
        statusLabel.stringValue = Status.scanning
        scanButton.isEnabled = false
        connectButton.isEnabled = false
        onScanAgain?()
    }

    @objc private func cancelTapped() { close() }
}

// ── Table ────────────────────────────────────────────────────────────────────

extension DevicePickerWindowController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { devices.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let device = devices[row]
        let cell = NSTableCellView()

        let name = NSTextField(labelWithString: device.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.frame = NSRect(x: 8, y: 9, width: Layout.signalColumnX - 8, height: 16)
        cell.addSubview(name)

        let signal = NSTextField(labelWithString: Self.signalDescription(device.rssi))
        signal.font = .systemFont(ofSize: 11)
        signal.textColor = .secondaryLabelColor
        signal.alignment = .right
        signal.frame = NSRect(x: Layout.signalColumnX, y: 9,
                              width: (tableColumn?.width ?? 280) - Layout.signalColumnX - 8,
                              height: 16)
        cell.addSubview(signal)

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        connectButton.isEnabled = tableView.selectedRow >= 0
    }

    /// Plain-language signal strength — a raw dBm figure means nothing to most
    /// people, and the only decision it informs is "which one is nearer".
    private static func signalDescription(_ rssi: Int) -> String {
        switch rssi {
        case (-50)...:      return "Excellent"
        case (-70)..<(-50): return "Good"
        case (-85)..<(-70): return "Fair"
        default:            return "Weak"
        }
    }
}
