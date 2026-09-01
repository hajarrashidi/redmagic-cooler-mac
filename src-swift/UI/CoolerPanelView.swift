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
final class CoolerPanelView: PanelRowView {

    /// The one thing the panel has to say beyond its numbers.
    ///
    /// These were four banner rows scattered down the menu, each appearing and
    /// disappearing on its own. They are mutually exclusive — every one of them
    /// is a fact about the cooler this panel already describes — so they belong
    /// on its last line, where the reader is already looking, and where a menu
    /// that gains and loses rows stops jumping under the cursor.
    enum Note: Equatable {
        /// A write is in flight and the controls are locked out.
        case switching
        /// Manual holds its level until the user changes it — the one state the
        /// app will not leave on its own.
        case manualStaysOn
        /// Linked and commanded on, but the hardware's own switch looks off.
        case powerSwitchOff
        /// Auto is armed and deliberately idle below its threshold.
        case autoWaiting(engageC: Int)
        /// The manual auto-off timer ran down and switched the cooler off.
        case manualTimedOut

        var text: String {
            switch self {
            case .switching:          return "Switching… please wait"
            case .manualStaysOn:      return "Manual stays on until you turn it off"
            case .powerSwitchOff:     return "Cooler's power switch is off"
            case .autoWaiting(let c): return "Waiting for the Mac to reach \(c)°C"
            case .manualTimedOut:     return "Auto-off timer ended Manual cooling"
            }
        }

        var symbol: String {
            switch self {
            case .switching:      return "arrow.triangle.2.circlepath"
            case .manualStaysOn,
                 .manualTimedOut: return "exclamationmark.triangle"
            case .powerSwitchOff: return "power.circle.fill"
            case .autoWaiting:    return "thermometer.medium"
            }
        }

        var tint: NSColor {
            switch self {
            case .switching: return .systemBlue
            // A genuine hardware fault: the app is commanding a cooler that
            // cannot answer. This one earns the amber.
            case .powerSwitchOff: return .systemOrange
            // Plain ink. Manual staying on is the mode working as documented,
            // not a fault, and an amber line that is on screen for the whole of
            // every manual session teaches the reader to ignore amber.
            case .manualStaysOn,
                 .manualTimedOut: return .labelColor
            // Auto idling below its threshold is the autopilot working, not a
            // warning about it.
            case .autoWaiting: return .secondaryLabelColor
            }
        }
    }

    /// Everything the panel draws, passed in one value so the view holds no
    /// opinions about where any of it came from.
    struct ViewModel {
        var isConnected = false
        var phase: ConnectionPhase = .idle
        var deviceModelName: String?
        var telemetry: CoolerTelemetry?
        var mode: CoolingMode = .off
        /// The cooler is linked and commanded on, but its physical switch looks
        /// to be off. The fan is then drawn still: showing it spinning while the
        /// hardware sits idle is the single most misleading thing this panel can
        /// do, because the spin is the main "it's working" cue.
        var deviceLooksPoweredOff = false
        var note: Note?
    }

    var onConnect: (() -> Void)?

    private var model = ViewModel()
    private var noteSymbol: NSImage?
    private let connectButton = PillButton(title: "Connect")
    private static let noteSymbolSize: CGFloat = 10

    // ── Metrics ──────────────────────────────────────────────────────────────

    private static let panelPad = UIStyle.panelPad
    private static let panelContentX = UIStyle.panelContentX
    /// The animated fan: its glyph size, and the lane reserved for it so
    /// telemetry cells never run underneath it.
    private static let fanSize: CGFloat = 26
    private static let fanLane = fanSize + 10
    private static let cellLabelFont = NSFont.systemFont(ofSize: 9)
    /// Larger than the section captions elsewhere: this names the device the
    /// whole panel is about, and at 9pt it read as another field label.
    private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let titleHeight: CGFloat = 16
    private static let statusFont = UIStyle.captionFont
    private static let statusHeight = UIStyle.text("A", statusFont).size().height
    /// The link line's ink. Blue still means "connected", but held well back —
    /// it confirms something the moving numbers beside it already imply.
    private static let linkColor = NSColor.systemBlue.withAlphaComponent(0.75)

    // Measured from the fonts themselves, so the panel height stays correct if
    // any of them are restyled — a hand-tuned height silently clips its last
    // row the moment a font changes.
    private static let cellLabelHeight = UIStyle.text("A", cellLabelFont).size().height
    private static let cellValueHeight = UIStyle.text("0", UIStyle.valueFont).size().height

    private static let noteGap: CGFloat = 7
    private static let noteHeight = UIStyle.text("A", UIStyle.captionFont).size().height
    /// The note's line is always reserved, even with nothing to say. A panel
    /// that grew and shrank with it would have to resize its row, and `NSMenu`
    /// does not re-lay out a row's view while the menu is open — which is
    /// exactly when every one of these notes appears.
    static let panelHeight =
        panelPad + titleHeight + statusHeight + 4
        + cellLabelHeight + 2 + cellValueHeight
        + noteGap + noteHeight + panelPad

    /// The panel plus the bottom padding that used to belong to the status
    /// card's own frame — this row is the last thing before the separator.
    static let height = panelHeight + UIStyle.hPad

    // ── Fan animation ────────────────────────────────────────────────────────

    private var fanAngle: CGFloat = 0
    private var animationTimer: Timer?
    /// Spin rate, in radians per frame, per zone step.
    ///
    /// Halved from where it started. At 30fps the blades were stepping far
    /// enough between frames to strobe — the eye reads a fast wheel with a
    /// coarse step as stuttering backwards, not as speed — so the slower sweep
    /// actually looks more like a spinning fan than the quick one did.
    private static let spinRatePerZone: CGFloat = 0.055
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
        // Re-tinting a template symbol allocates an image; this runs on every
        // telemetry frame, so the note's icon is rebuilt only when the note
        // itself changes.
        if model.note != self.model.note {
            noteSymbol = model.note.map {
                Self.tinted($0.symbol, size: Self.noteSymbolSize, color: $0.tint)
            } ?? nil
        }
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
            // Positive, and this view is flipped — which mirrors the y-axis,
            // so `rotate(byRadians:)`'s usual anticlockwise sweep lands on
            // screen as clockwise. Which is the way a fan turns.
            self.fanAngle += CGFloat(zone) * Self.spinRatePerZone
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
        // Lays down the menu backdrop; this row paints over it.
        super.draw(dirtyRect)
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
        // One fixed grey. The blades used to carry the LED's colour, which put
        // a second colour-coded readout next to the temperature — and made the
        // fan look like it was reporting something when it is only spinning.
        FanGlyph.draw(in: rect, angleRadians: fanAngle,
                      color: .tertiaryLabelColor, zone: runningZone)
    }

    /// Cooler telemetry, or the connection phase when there's no link.
    private func drawContents(y: inout CGFloat) {
        let pad = Self.panelContentX
        let deviceTitle = model.deviceModelName?.uppercased() ?? "COOLER"
        let title = UIStyle.text(deviceTitle, Self.titleFont, .secondaryLabelColor)
        title.draw(at: NSPoint(x: pad, y: y))

        y += Self.titleHeight

        // The link's own line, under the name of the thing it connects to. It
        // says the same thing the phase line says when there is no link, so the
        // two share a slot rather than one of them being a mark tucked beside
        // the title — an icon there had to carry "connected, over Bluetooth,
        // right now" on its own, which is more than a 6pt glyph can say.
        let status = model.isConnected
            ? UIStyle.text("Connected over Bluetooth", Self.statusFont, Self.linkColor)
            : UIStyle.text(model.phase.statusText, Self.statusFont, phaseColor())
        // Kept clear of the Connect button, which shares this line's height.
        let statusWidth = model.isConnected
            ? bounds.width - pad * 2 - Self.fanLane
            : connectButton.frame.minX - pad - 8
        status.draw(in: NSRect(x: pad, y: y, width: max(statusWidth, 1),
                               height: Self.statusHeight))
        y += Self.statusHeight + 4

        // Always at the panel's foot, whether or not the telemetry above it is
        // there to be pushed down.
        if let note = model.note {
            drawNote(note, y: Self.panelHeight - Self.panelPad - Self.noteHeight)
        }

        guard model.isConnected else { return }

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

    /// The note's icon, in its own colour. Template images can't be tinted at
    /// draw time the way a view's `contentTintColor` does it, so the symbol is
    /// rendered once into a coloured image — see `update`, which is what
    /// decides when "once" is.
    private static func tinted(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        return NSImage(size: base.size, flipped: false) { rect in
            color.set()
            base.draw(in: rect)
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// The note line: its icon, then its message, along the panel's foot.
    private func drawNote(_ note: Note, y: CGFloat) {
        let pad = Self.panelContentX
        var x = pad
        if let noteSymbol {
            let size = noteSymbol.size
            noteSymbol.draw(in: NSRect(x: x, y: y + (Self.noteHeight - size.height) / 2,
                                       width: size.width, height: size.height),
                            from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: nil)
            x += size.width + 5
        }
        UIStyle.text(note.text, UIStyle.captionFont, note.tint)
            .draw(in: NSRect(x: x, y: y, width: bounds.width - x - pad,
                             height: Self.noteHeight))
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

    private func phaseColor() -> NSColor {
        switch model.phase {
        case .bluetoothOff:          return .systemRed
        case .bluetoothUnauthorized: return .systemOrange
        case .idle:                  return .tertiaryLabelColor
        default:                     return .secondaryLabelColor
        }
    }
}
