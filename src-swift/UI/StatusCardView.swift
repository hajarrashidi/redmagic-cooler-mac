import AppKit

/// The card at the top of the menu: Mac temperature, cooler state and live
/// telemetry, drawn as one custom view.
///
/// Everything is drawn rather than composed from subviews. The layout is a
/// single top-to-bottom flow whose sections appear conditionally (telemetry
/// only when connected, and only for the fields the device actually reports),
/// which is far simpler to express as a cursor walking down the card than as a
/// tree of views being shown and hidden.
final class StatusCardView: NSView {

    /// Derived from the panels rather than hand-tuned, so restyling a font or
    /// changing the padding can't leave the last row clipped.
    static var height: CGFloat {
        // Split into named parts: as one expression the type-checker crawls.
        let header: CGFloat = pad + logoSize + headerGap * 2
        let panels: CGFloat = macPanelHeight + panelGap + devicePanelHeight
        return header + panels + pad
    }

    /// Everything the card draws, passed in one value so the view holds no
    /// opinions about where any of it came from.
    struct ViewModel {
        var dieTempC: Double?
        var thermalState: ThermalState = .nominal
        var mode: CoolingMode = .off
        var telemetry: CoolerTelemetry?
        var isConnected = false
        var phase: ConnectionPhase = .idle
        var deviceModelName: String?
        var appMode: AppMode = .auto
        var autoProfile: AutoProfile = .standard
        /// Tint for the animated fan — mirrors the active LED colour.
        var fanTint: NSColor = .secondaryLabelColor
        /// The cooler is linked and commanded on, but its physical switch looks
        /// to be off. The fan is then drawn still: showing it spinning while the
        /// hardware sits idle is the single most misleading thing this card can
        /// do, because the spin is the main "it's working" cue.
        var deviceLooksPoweredOff = false
    }

    private var model = ViewModel()

    // ── Fan animation ────────────────────────────────────────────────────────

    private var fanAngle: CGFloat = 0
    private var animationTimer: Timer?
    /// Spin rate, in radians per frame, per zone step.
    private static let spinRatePerZone: CGFloat = 0.11
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    // ── Metrics ──────────────────────────────────────────────────────────────

    private static let pad = UIStyle.hPad
    // Panel metrics live in UIStyle now, shared with every panelled section of
    // the menu, so this card and the control rows below it can never drift.
    private static let panelPad = UIStyle.panelPad
    private static let panelInset = UIStyle.panelInset
    private static let panelContentX = UIStyle.panelContentX
    private static let panelGap: CGFloat = 10
    private static let panelRadius = UIStyle.panelRadius
    /// The animated fan in the cooler panel: its glyph size, and the lane
    /// reserved for it so telemetry cells never run underneath it.
    private static let fanSize: CGFloat = 26
    private static let fanLane = fanSize + 10
    private static let logoSize: CGFloat = 18
    /// Gap below the brand header, used twice: once by the header's own
    /// bottom margin and once before the first panel.
    private static let headerGap: CGFloat = 7
    private static let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let tempFont = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .light)
    private static let stateFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    private static let badgeFont = NSFont.systemFont(ofSize: 9, weight: .medium)
    private static let cellLabelFont = NSFont.systemFont(ofSize: 9)

    /// Die temperatures spanning the header progress bar, in °C.
    private static let barRange: ClosedRange<Double> = 30...100

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = .width
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(_ model: ViewModel) {
        self.model = model
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

    // ── Drawing ──────────────────────────────────────────────────────────────

    /// The zone the fan glyph should read as. Distinct from the commanded mode:
    /// with no link, or with the device's own switch off, nothing is actually
    /// spinning however the app has set it.
    private var runningZone: CoolingMode.Zone {
        guard model.isConnected, !model.deviceLooksPoweredOff else { return .off }
        return model.mode.zone
    }

    override func draw(_ dirtyRect: NSRect) {
        var y = Self.pad
        drawBrandHeader(y: &y)
        y += Self.headerGap

        // Each group sits on its own surface. Hairline dividers put the Mac's
        // readings and the cooler's in one undifferentiated column, which read
        // as a single list of numbers rather than two sources; panels make the
        // boundary obvious at a glance. Settings keeps its own titled group
        // further down the menu.
        drawPanel(at: y, height: Self.macPanelHeight)
        var macY = y + Self.panelPad
        drawMacSection(y: &macY)
        y += Self.macPanelHeight + Self.panelGap

        drawPanel(at: y, height: Self.devicePanelHeight)
        drawFan(panelTop: y)
        var deviceY = y + Self.panelPad
        drawDeviceSection(y: &deviceY)
    }

    private func drawPanel(at y: CGFloat, height: CGFloat) {
        let inset = Self.panelInset
        let rect = NSRect(x: inset, y: y, width: bounds.width - inset * 2, height: height)
        UIStyle.panelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Self.panelRadius,
                     yRadius: Self.panelRadius).fill()
    }

    /// The spinning fan, centred vertically along the cooler panel's trailing
    /// edge — it lives with the device it narrates, not in the brand header.
    private func drawFan(panelTop: CGFloat) {
        let rect = NSRect(x: bounds.width - Self.panelContentX - Self.fanSize,
                          y: panelTop + (Self.devicePanelHeight - Self.fanSize) / 2,
                          width: Self.fanSize, height: Self.fanSize)
        FanGlyph.draw(in: rect, angleRadians: fanAngle,
                      color: model.fanTint, zone: runningZone)
    }

    // Measured once from the fonts themselves, so `height` below stays correct
    // if any of them are restyled — a hand-tuned card height silently clips its
    // last row the moment a font changes.
    private static let tempTextHeight = UIStyle.text("0", tempFont).size().height
    private static let cellLabelHeight = UIStyle.text("A", cellLabelFont).size().height
    private static let cellValueHeight = UIStyle.text("0", UIStyle.valueFont).size().height

    static let macPanelHeight =
        panelPad + 13 + tempTextHeight + 6 + 4 + panelPad
    static let devicePanelHeight =
        panelPad + 14 + cellLabelHeight + 2 + cellValueHeight + panelPad

    /// The running app's version, shown beside the title. Read once — the
    /// bundle can't change under a running process.
    private static let versionText: String? =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "v\($0)" }

    /// Logo, title, version and the mode badge.
    private func drawBrandHeader(y: inout CGFloat) {
        let pad = Self.pad
        let logoSize = Self.logoSize
        RedMagicLogo.drawR(in: NSRect(x: pad, y: y + 1, width: logoSize, height: logoSize))

        let title = UIStyle.text("REDMAGIC COOLER", Self.headerFont)
        let titleX = pad + logoSize + 7
        title.draw(at: NSPoint(x: titleX, y: y + 2))

        if let versionText = Self.versionText {
            let version = UIStyle.text(versionText, UIStyle.captionFont, .tertiaryLabelColor)
            version.draw(at: NSPoint(x: titleX + title.size().width + 8, y: y + 5))
        }

        let (badgeText, badgeColor) = modeBadge()
        let badge = UIStyle.text(badgeText, Self.badgeFont, badgeColor)
        badge.draw(at: NSPoint(x: bounds.width - pad - badge.size().width, y: y + 5))

        y += logoSize + Self.headerGap
    }

    /// Mac model, thermal pressure, die temperature and the heat bar.
    private func drawMacSection(y: inout CGFloat) {
        let pad = Self.panelContentX
        UIStyle.text(SystemInfo.macModel, UIStyle.sectionFont, .tertiaryLabelColor)
            .draw(at: NSPoint(x: pad, y: y))

        let state = UIStyle.text(model.thermalState.rawValue, Self.stateFont, .secondaryLabelColor)
        state.draw(at: NSPoint(x: bounds.width - pad - state.size().width, y: y - 1))
        y += 13

        let temp = UIStyle.text(SystemInfo.formatTemp(model.dieTempC),
                                Self.tempFont, UIStyle.textHeatColor(model.dieTempC))
        let tempHeight = temp.size().height
        temp.draw(in: NSRect(x: pad, y: y, width: 160, height: tempHeight))
        y += tempHeight + 6

        drawHeatBar(y: y)
        y += 4
    }

    private func drawHeatBar(y: CGFloat) {
        let pad = Self.panelContentX
        let width = bounds.width - pad * 2
        let track = NSRect(x: pad, y: y, width: width, height: 4)

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()

        guard let temp = model.dieTempC else { return }
        let span = Self.barRange.upperBound - Self.barRange.lowerBound
        let fraction = CGFloat(((temp - Self.barRange.lowerBound) / span).clamped(to: 0...1))
        guard fraction > 0 else { return }

        UIStyle.heatColor(temp).setFill()
        NSBezierPath(roundedRect: NSRect(x: pad, y: y, width: width * fraction, height: 4),
                     xRadius: 2, yRadius: 2).fill()
    }

    /// Cooler telemetry, or the connection phase when there's no link.
    private func drawDeviceSection(y: inout CGFloat) {
        let pad = Self.panelContentX
        let deviceTitle = model.deviceModelName?.uppercased() ?? "COOLER"
        UIStyle.text(deviceTitle, UIStyle.sectionFont, .tertiaryLabelColor)
            .draw(at: NSPoint(x: pad, y: y))
        y += 14

        guard model.isConnected else {
            UIStyle.text(model.phase.statusText, Self.cellLabelFont, phaseColor())
                .draw(at: NSPoint(x: pad, y: y))
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
        let labelHeight = UIStyle.text("A", Self.cellLabelFont).size().height
        let valueHeight = UIStyle.text("0", UIStyle.valueFont).size().height

        for (index, cell) in cells.enumerated() {
            let x = pad + cellWidth * CGFloat(index)
            UIStyle.text(cell.label, Self.cellLabelFont, .tertiaryLabelColor)
                .draw(in: NSRect(x: x, y: y, width: cellWidth, height: labelHeight))
            UIStyle.text(cell.value, UIStyle.valueFont, .secondaryLabelColor)
                .draw(in: NSRect(x: x, y: y + labelHeight + 2, width: cellWidth, height: valueHeight))
        }
    }

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

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func phaseColor() -> NSColor {
        switch model.phase {
        case .bluetoothOff:          return .systemRed
        case .bluetoothUnauthorized: return .systemOrange
        case .idle:                  return .tertiaryLabelColor
        default:                     return .secondaryLabelColor
        }
    }

    /// The badge top-right: the autopilot's profile, or the manual mode.
    private func modeBadge() -> (String, NSColor) {
        guard model.isConnected else { return ("", .clear) }
        if model.appMode == .auto {
            return ("Auto · \(model.autoProfile.displayName)", .systemBlue)
        }
        let color: NSColor
        switch model.mode.zone {
        case .off:    color = .secondaryLabelColor
        case .low:    color = .systemTeal
        case .medium: color = .systemCyan
        case .max:    color = .systemRed
        }
        return (model.mode.displayName, color)
    }
}
