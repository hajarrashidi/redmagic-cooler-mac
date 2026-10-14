import AppKit

/// A small window listing every temperature this Mac reports, with live values,
/// for choosing which one Auto mode follows.
///
/// A window rather than a menu section: the list is long (the die alone has ten
/// sensors) and the menu's rows are hand-drawn panels, not a place for a table.
final class TemperatureSourceWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                      NSWindowDelegate {

    /// Called when the user picks a source.
    var onSelect: ((ThermalMonitor.Source) -> Void)?

    private enum Item {
        case header(String)
        case choice(ThermalMonitor.Source, celsius: Double)
    }

    private var current: ThermalMonitor.Source
    private var items = [Item]()
    private var window: NSWindow?
    private let table = NSTableView()
    private let footer = NSTextField(wrappingLabelWithString: "")
    private var refreshTimer: Timer?

    init(current: ThermalMonitor.Source) {
        self.current = current
        super.init()
    }

    func show(current: ThermalMonitor.Source) {
        self.current = current
        if window == nil { buildWindow() }
        reload()
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.reload() }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // ── Window ───────────────────────────────────────────────────────────────

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Temperature Source"
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Fixed frames rather than Auto Layout: with constraints the table's own
        // height (every sensor row) became the window's, and nothing scrolled.
        let marker = NSTableColumn(identifier: .init("marker"))
        marker.width = 22
        let name = NSTableColumn(identifier: .init("name"))
        name.width = 240
        let value = NSTableColumn(identifier: .init("value"))
        value.width = 70
        for column in [marker, name, value] { table.addTableColumn(column) }
        table.headerView = nil
        table.rowHeight = 22
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 460))

        footer.stringValue = "The chosen temperature drives Auto mode, the status card and the "
            + "light's Auto colour. If a sensor goes missing, the SoC die average is used."
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.frame = NSRect(x: 16, y: 14, width: 388, height: 44)
        footer.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(footer)

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 66, width: 388, height: 378))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        content.addSubview(scroll)

        window.contentView = content
        table.sizeLastColumnToFit()
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // ── Data ─────────────────────────────────────────────────────────────────

    /// Rebuilds the list from a fresh sample and restores the highlight, so the
    /// live values keep moving without the selection jumping.
    private func reload() {
        let sensors = ThermalMonitor.sensors()
        var rebuilt = [Item]()

        rebuilt.append(.header("Groups"))
        for source in ThermalMonitor.Source.groups {
            if let celsius = ThermalMonitor.reading(for: source, in: sensors) {
                rebuilt.append(.choice(source, celsius: celsius))
            }
        }
        rebuilt.append(.header("Individual sensors"))
        for sensor in ThermalMonitor.namedSensors(from: sensors) {
            rebuilt.append(.choice(.sensor(sensor.name), celsius: sensor.celsius))
        }
        items = rebuilt
        table.reloadData()

        if let row = items.firstIndex(where: {
            if case .choice(let source, _) = $0 { return source == current }
            return false
        }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .choice = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail

        switch items[row] {
        case .header(let title):
            // Group rows span every column; only the first view is used.
            text.stringValue = title.uppercased()
            text.font = .systemFont(ofSize: 10, weight: .semibold)
            text.textColor = .secondaryLabelColor
        case .choice(let source, let celsius):
            switch tableColumn?.identifier.rawValue {
            case "marker":
                text.stringValue = (source == current) ? "✓" : ""
            case "name":
                text.stringValue = source.title
                    + ((source == .dieAverage) ? "  (default)" : "")
            default:
                text.stringValue = SystemInfo.formatTemp(celsius)
                text.alignment = .right
                text.textColor = .secondaryLabelColor
            }
        }
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, case .choice(let source, _) = items[row], source != current else { return }
        current = source
        onSelect?(source)
        reload()
    }
}
