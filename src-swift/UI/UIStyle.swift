import AppKit

/// Shared visual constants and drawing helpers.
///
/// Every menu row pulls its paddings, fonts and colours from here, so the menu
/// stays visually consistent and restyling is a one-file change.
enum UIStyle {

    // ── Metrics ──────────────────────────────────────────────────────────────

    /// The width the menu's proportions were drawn against. Every horizontal
    /// metric below is expressed as its value at *this* width and scaled to the
    /// real one, so widening the menu widens its panels, their insets and their
    /// corners together. Stretching the panels alone would leave a wider menu
    /// looking like the same menu with padding sucked out of it.
    private static let baseWidth: CGFloat = 300

    /// Width of every custom menu row. NSMenu sizes itself to its widest item,
    /// so these must agree or rows will not line up.
    static let menuWidth: CGFloat = 330

    /// Rounded to whole points: half-pixel insets blur every edge that lands
    /// on them, and the error never exceeds half a point anyway.
    private static func scaled(_ value: CGFloat) -> CGFloat {
        (value * menuWidth / baseWidth).rounded()
    }

    /// Horizontal inset matching the system's own menu-item text alignment.
    static let hPad = scaled(14)

    // ── Panels ───────────────────────────────────────────────────────────────
    //
    // The card-on-a-menu look every section shares: a soft rounded surface
    // inset from the menu's edges, with content indented a further step — the
    // same arrangement System Settings uses for its group boxes. The status
    // card introduced it; the control sections reuse the exact same numbers so
    // the whole menu reads as one system.

    /// Margin between a panel's edge and the menu's.
    static let panelInset = scaled(8)
    /// Vertical gap between two panels stacked in the menu. Shared, because the
    /// panels either side of it are separate menu rows and each supplies half
    /// the run-up to it.
    static let panelGap: CGFloat = 10
    /// Vertical breathing room inside a panel: the gap above the first piece
    /// of content and below the last. Every panel row applies it at both of
    /// its own edges, so a row junction inside a section reads as two of
    /// these — one uniform rhythm across the whole menu, status card included.
    static let panelPad: CGFloat = 8
    /// Horizontal breathing room inside a panel.
    static let panelContentPad = scaled(12)
    /// Left edge of anything drawn inside a panel.
    static let panelContentX = panelInset + panelContentPad
    static let panelRadius = scaled(9)
    /// Fill for a panel: a barely-there wash that reads as a raised card
    /// against the menu behind it. Deliberately faint — the panels are grouping
    /// devices, not surfaces in their own right.
    static var panelColor: NSColor { NSColor.labelColor.withAlphaComponent(0.045) }

    // ── The menu's own backdrop ──────────────────────────────────────────────

    /// Laid down edge to edge by every row, behind everything else it draws.
    ///
    /// `NSMenu` renders itself as a vibrant, translucent window and AppKit
    /// exposes no way to make that opaque. What it does expose is the rows —
    /// and in this menu nearly every item is a custom view, which can paint. So
    /// each row covers its own slice of the window, and between them they cover
    /// the menu.
    ///
    /// This is the number to turn for more or less see-through: 1.0 is fully
    /// opaque, 0 hands the menu back to the system's vibrancy.
    static var menuBackdrop: NSColor { NSColor.white.withAlphaComponent(0.75) }

    /// The radius of the menu window's own rounded corners, matched by the
    /// first and last rows so the backdrop can't square off a corner the system
    /// rounded. Erring large costs a hairline of the menu's own background at
    /// the corner; erring small leaves a visible square shoulder — so this is
    /// deliberately on the generous side.
    static let menuCornerRadius: CGFloat = 10

    /// Which end of the menu a row sits at, and therefore which of its corners
    /// have to follow the window's.
    struct MenuEdges: OptionSet {
        let rawValue: Int
        static let top = MenuEdges(rawValue: 1 << 0)
        static let bottom = MenuEdges(rawValue: 1 << 1)
    }

    static func drawMenuBackdrop(in view: NSView, edges: MenuEdges) {
        menuBackdrop.setFill()
        guard !edges.isEmpty else {
            view.bounds.fill()
            return
        }
        let roundsTop = edges.contains(.top)
        let roundsBottom = edges.contains(.bottom)
        roundedPath(view.bounds,
                    radius: menuCornerRadius,
                    roundMinY: view.isFlipped ? roundsTop : roundsBottom,
                    roundMaxY: view.isFlipped ? roundsBottom : roundsTop).fill()
    }

    /// Where a row sits within a multi-row panel, which decides which of its
    /// corners are rounded. Rows stack with no gap in the menu, so a section
    /// drawn as top → middle → bottom reads as one continuous surface.
    enum PanelSegment {
        case only, top, middle, bottom

        var roundsVisualTop: Bool    { self == .only || self == .top }
        var roundsVisualBottom: Bool { self == .only || self == .bottom }
    }

    /// Fills `view`'s bounds with a panel surface, rounding only the corners
    /// `segment` calls for. Handles flipped and unflipped views alike — the
    /// segment speaks in visual terms and the geometry is resolved here.
    static func drawPanel(_ segment: PanelSegment, in view: NSView) {
        let rect = NSRect(x: panelInset, y: 0,
                          width: view.bounds.width - panelInset * 2,
                          height: view.bounds.height)
        let roundMinY = view.isFlipped ? segment.roundsVisualTop : segment.roundsVisualBottom
        let roundMaxY = view.isFlipped ? segment.roundsVisualBottom : segment.roundsVisualTop
        panelColor.setFill()
        panelPath(rect, roundMinY: roundMinY, roundMaxY: roundMaxY).fill()
    }

    /// A rect rounded only along the chosen y-edges, for panel segments.
    static func panelPath(_ rect: NSRect, roundMinY: Bool, roundMaxY: Bool) -> NSBezierPath {
        roundedPath(rect, radius: panelRadius, roundMinY: roundMinY, roundMaxY: roundMaxY)
    }

    /// A rect rounded only along the chosen y-edges. Shared by the panels and
    /// by the menu backdrop, which round to different radii.
    static func roundedPath(_ rect: NSRect, radius: CGFloat,
                            roundMinY: Bool, roundMaxY: Bool) -> NSBezierPath {
        let rMin: CGFloat = roundMinY ? radius : 0
        let rMax: CGFloat = roundMaxY ? radius : 0
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY + rMin))
        path.appendArc(withCenter: NSPoint(x: rect.minX + rMin, y: rect.minY + rMin),
                       radius: rMin, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: rect.maxX - rMin, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - rMin, y: rect.minY + rMin),
                       radius: rMin, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - rMax))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - rMax, y: rect.maxY - rMax),
                       radius: rMax, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: rect.minX + rMax, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + rMax, y: rect.maxY - rMax),
                       radius: rMax, startAngle: 90, endAngle: 180)
        path.close()
        return path
    }

    // ── Fonts ────────────────────────────────────────────────────────────────

    static let sectionFont = NSFont.systemFont(ofSize: 9,  weight: .semibold)
    static let captionFont = NSFont.systemFont(ofSize: 10, weight: .regular)
    static let bodyFont    = NSFont.systemFont(ofSize: 11, weight: .regular)
    /// Monospaced digits stop telemetry values jittering as they update.
    static let valueFont   = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// The small uppercase caption that titles a control row.
    ///
    /// Six rows built this same field by hand. Only the font and colour are
    /// shared — each row still places its own header, because they sit at
    /// different heights within their layouts.
    static func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = sectionFont
        label.textColor = .tertiaryLabelColor
        return label
    }

    static func text(_ string: String,
                     _ font: NSFont,
                     _ color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: string,
                           attributes: [.font: font, .foregroundColor: color])
    }

    /// Draws a small kerned uppercase section label at `point` (flipped, y-down).
    static func drawSectionHeader(_ title: String, at point: NSPoint) {
        NSAttributedString(string: title.uppercased(), attributes: [
            .font: sectionFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 0.6,
        ]).draw(at: point)
    }

    /// Heat-graded colour for a Mac die temperature (°C). Thresholds are
    /// presentation-only and intentionally independent of the autopilot's
    /// engage points — this is "how hot does this feel", not "what will we do".
    static func heatColor(_ celsius: Double?) -> NSColor {
        guard let celsius else { return .secondaryLabelColor }
        switch celsius {
        case ..<60: return .systemGreen
        case ..<75: return .systemYellow
        case ..<85: return .systemOrange
        default:    return .systemRed
        }
    }

    /// Heat colour for *text*. Identical to `heatColor` except the cool range
    /// reads as plain label ink — a big green number looked like a status
    /// light, not a reading. The warning colours stay so heat still stands out.
    ///
    /// That ink is softened, because at 26pt full-strength `labelColor` is the
    /// heaviest mark in the menu and pulls the eye to a number that, while the
    /// Mac is cool, is the least interesting thing on the card. The warning
    /// colours keep their full strength — when they appear, they *are* the
    /// point.
    static func textHeatColor(_ celsius: Double?) -> NSColor {
        guard let celsius, celsius >= 60 else {
            return NSColor.labelColor.withAlphaComponent(0.55)
        }
        return heatColor(celsius)
    }
}

/// Base class for a menu row that sits inside a section panel.
///
/// A section spanning several rows can't draw one background — each row is its
/// own menu-item view — so every row draws its slice instead, and `refresh()`
/// (or the builder, for sections whose membership is fixed) tells it which
/// slice it currently is. Subclasses that override `draw` must call `super`
/// first, so the panel stays underneath their content.
class PanelRowView: NSView {

    /// The row's place in its section panel; nil draws no panel at all.
    var panelSegment: UIStyle.PanelSegment? {
        didSet { if panelSegment != oldValue { needsDisplay = true } }
    }

    /// Set on whichever rows are currently first and last in the menu, so the
    /// backdrop follows the window's rounded corners instead of squaring them.
    var menuEdges: UIStyle.MenuEdges = [] {
        didSet { if menuEdges != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        UIStyle.drawMenuBackdrop(in: self, edges: menuEdges)
        if let panelSegment {
            UIStyle.drawPanel(panelSegment, in: self)
        }
    }
}
