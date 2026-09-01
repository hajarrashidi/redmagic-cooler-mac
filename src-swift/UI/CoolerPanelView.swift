import AppKit

/// The cooler's own panel: its model and live telemetry with the animated fan
/// while the link is up, and the Connect button while it isn't.
///
/// This used to be the lower half of `StatusCardView`. It is a menu row of its
/// own now so that it can be hidden entirely, because there are two states in
/// which it has nothing to say: with no remembered cooler there is nothing for
/// a Connect button to aim at, and while the picker is listing every device in
/// range a panel reading "Not connected" above it is noise. Hiding a *row* is
/// something `NSMenu` re-lays out live; resizing a row's view — which is what
/// collapsing a panel inside the status card would have needed — is not.
final class CoolerPanelView: NSView {

    /// Everything the panel draws, passed in one value so the view holds no
    /// opinions about where any of it came from.
    struct ViewModel {
        var isConnected = false
        var phase: ConnectionPhase = .idle
        var deviceModelName: String?
        var telemetry: CoolerTelemetry?
        var mode: CoolingMode = .off
        /// Tint for the animated fan — mirrors the active LED colour.
        var fanTint: NSColor = .secondaryLabelColor
        /// The cooler is linked and commanded on, but its physical switch looks
        /// to be off. The fan is then drawn still: showing it spinning while the
        /// hardware sits idle is the single most misleading thing this panel can
        /// do, because the spin is the main "it's working" cue.
        var deviceLooksPoweredOff = false
    }

    var onConnect: (() -> Void)?

    private var model = ViewModel()
    private let connectButton = PillButton(title: "Connect")

    // ── Metrics ──────────────────────────────────────────────────────────────

    private static let panelPad = UIStyle.panelPad
    private static let panelContentX = UIStyle.panelContentX
    /// The animated fan: its glyph size, and the lane reserved for it so
    /// telemetry cells never run underneath it.
    private static let fanSize: CGFloat = 26
    private static let fanLane = fanSize + 10
    private static let cellLabelFont = NSFont.systemFont(ofSize: 9)

    // Measured from the fonts themselves, so the panel height stays correct if
    // any of them are restyled — a hand-tuned height silently clips its last
    // row the moment a font changes.
    private static let cellLabelHeight = UIStyle.text("A", cellLabelFont).size().height
    private static let cellValueHeight = UIStyle.text("0", UIStyle.valueFont).size().height

    static let panelHeight =
        panelPad + 14 + cellLabelHeight + 2 + cellValueHeight + panelPad

    /// The panel plus the bottom padding that used to belong to the status
    /// card's own frame — this row is the last thing before the separator.
    static let height = panelHeight + UIStyle.hPad

    // ── Fan animation ────────────────────────────────────────────────────────

    private var fanAngle: CGFloat = 0
    private var animationTimer: Timer?
    /// Spin rate, in radians per frame, per zone step.
    private static let spinRatePerZone: CGFloat = 0.11
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = .width

        connectButton.onClick = { [weak self] in self?.onConnect?() }
        // Anchored to the trailing edge, like the fan it stands in for.
        connectButton.autoresizingMask = .minXMargin
        addSubview(connectButton)
        layOutConnectButton()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(_ model: ViewModel) {
        self.model = model
        syncConnectButton()
        needsDisplay = true
    }

    // ── Animation, driven by the menu opening and closing ────────────────────

    /// The fan only spins while the menu is on screen; a timer running behind a
    /// closed menu would wake the CPU 30×/s to draw nothing.
    func startAnimating() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            guard let self, self.model.isConnected else { return }
            guard !self.model.deviceLooksPoweredOff else { return }
            let zone = self.model.mode.zone.rawValue
            guard zone > 0 else { return }
            self.fanAngle -= CGFloat(zone) * Self.spinRatePerZone
            self.needsDisplay = true
        }
        // .common keeps it running while the menu tracks mouse events.
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    // ── Connect button ───────────────────────────────────────────────────────

    private func syncConnectButton() {
        connectButton.isHidden = model.isConnected
        guard !model.isConnected else { return }
        // The title changes width with the phase, so the trailing edge has to
        // be re-anchored rather than merely relabelled.
        connectButton.title = model.phase.connectButtonTitle
        connectButton.isEnabled = model.phase.allowsConnectAction
        layOutConnectButton()
    }

    private func layOutConnectButton() {
        let width = connectButton.fittingWidth
        connectButton.frame = NSRect(
            x: bounds.width - Self.panelContentX - width,
            y: (Self.panelHeight - PillButton.height) / 2,
            width: width, height: PillButton.height)
    }

    // ── Drawing ──────────────────────────────────────────────────────────────

    /// The zone the fan glyph should read as. Distinct from the commanded mode:
    /// with no link, or with the device's own switch off, nothing is actually
    /// spinning however the app has set it.
    private var runningZone: CoolingMode.Zone {
        guard model.isConnected, !model.deviceLooksPoweredOff else { return .off }
        return model.mode.zone
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = UIStyle.panelInset
        let rect = NSRect(x: inset, y: 0,
                          width: bounds.width - inset * 2, height: Self.panelHeight)
        UIStyle.panelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: UIStyle.panelRadius,
                     yRadius: UIStyle.panelRadius).fill()

        // The fan narrates a running cooler. With no link the Connect button
        // occupies that lane instead, so only one of the two is ever drawn.
        if model.isConnected { drawFan() }

        var y = Self.panelPad
        drawContents(y: &y)
    }

    /// The spinning fan, centred vertically along the panel's trailing edge.
    private func drawFan() {
        let rect = NSRect(x: bounds.width - Self.panelContentX - Self.fanSize,
                          y: (Self.panelHeight - Self.fanSize) / 2,
                          width: Self.fanSize, height: Self.fanSize)
        FanGlyph.draw(in: rect, angleRadians: fanAngle,
                      color: model.fanTint, zone: runningZone)
    }

    /// Cooler telemetry, or the connection phase when there's no link.
    private func drawContents(y: inout CGFloat) {
        let pad = Self.panelContentX
        let deviceTitle = model.deviceModelName?.uppercased() ?? "COOLER"
        let title = UIStyle.text(deviceTitle, UIStyle.sectionFont, .tertiaryLabelColor)
        title.draw(at: NSPoint(x: pad, y: y))

        // A live Bluetooth link is the one thing the panel could previously
        // only imply — the numbers move, so it must be connected. Say it, in
        // the same breath as the model name it belongs to.
        if model.isConnected {
            drawLinkBadge(x: pad + title.size().width + 7, y: y)
        }
        y += 14

        guard model.isConnected else {
            // Kept clear of the Connect button, which shares this line's height.
            let width = connectButton.frame.minX - pad - 8
            UIStyle.text(model.phase.statusText, Self.cellLabelFont, phaseColor())
                .draw(in: NSRect(x: pad, y: y, width: max(width, 1),
                                 height: Self.cellLabelHeight))
            return
        }

        let cells = telemetryCells()
        guard !cells.isEmpty else {
            UIStyle.text("—", Self.cellLabelFont, .tertiaryLabelColor)
                .draw(at: NSPoint(x: pad, y: y))
            return
        }

        // The fan occupies the panel's trailing edge; keep the cells clear of it.
        let cellWidth = (bounds.width - pad * 2 - Self.fanLane) / CGFloat(cells.count)
        for (index, cell) in cells.enumerated() {
            let x = pad + cellWidth * CGFloat(index)
            UIStyle.text(cell.label, Self.cellLabelFont, .tertiaryLabelColor)
                .draw(in: NSRect(x: x, y: y, width: cellWidth, height: Self.cellLabelHeight))
            UIStyle.text(cell.value, UIStyle.valueFont, .secondaryLabelColor)
                .draw(in: NSRect(x: x, y: y + Self.cellLabelHeight + 2,
                                 width: cellWidth, height: Self.cellValueHeight))
        }
    }

    /// A small radiating-antenna mark and the word "Connected", drawn beside
    /// the model name. Green rather than the fan's tint: this is about the
    /// link, not about how hard the cooler is working.
    private func drawLinkBadge(x: CGFloat, y: CGFloat) {
        let tint = NSColor.systemGreen
        let size: CGFloat = 9
        if let glyph = Self.linkSymbol {
            glyph.draw(in: NSRect(x: x, y: y - 1, width: size, height: size),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
        UIStyle.text("CONNECTED", UIStyle.sectionFont, tint)
            .draw(at: NSPoint(x: x + size + 4, y: y))
    }

    /// Tinted once and cached: this is redrawn on every telemetry frame, and
    /// re-tinting a template image each time is pure churn.
    private static let linkSymbol: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        guard let base = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                                 accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            NSColor.systemGreen.set()
            base.draw(in: rect)
            rect.fill(using: .sourceAtop)
            return true
        }
        return tinted
    }()

    /// Telemetry laid out as evenly spaced cells. A sensor reporting 0 is
    /// reporting "not measured yet", so it shows an em dash rather than 0°.
    private func telemetryCells() -> [(label: String, value: String)] {
        guard let telemetry = model.telemetry else { return [] }
        func temp(_ celsius: Int) -> String {
            celsius > 0 ? SystemInfo.formatTemp(celsius, degreeOnly: true) : "—"
        }
        var cells = [(label: String, value: String)]()
        cells.append(("Cold", temp(telemetry.coldC)))
        cells.append(("Hot", temp(telemetry.hotC)))
        cells.append(("Ambient", SystemInfo.formatTemp(telemetry.ambientC, degreeOnly: true)))
        if let rpm = telemetry.fanRPM {
            cells.append(("RPM", rpm > 0 ? "\(rpm)" : "—"))
        }
        return cells
    }

    private func phaseColor() -> NSColor {
        switch model.phase {
        case .bluetoothOff:          return .systemRed
        case .bluetoothUnauthorized: return .systemOrange
        case .idle:                  return .tertiaryLabelColor
        default:                     return .secondaryLabelColor
        }
    }
}
