import AppKit

/// Shared visual constants and drawing helpers.
///
/// Every menu row pulls its paddings, fonts and colours from here, so the menu
/// stays visually consistent and restyling is a one-file change.
enum UIStyle {

    // ── Metrics ──────────────────────────────────────────────────────────────

    /// Width of every custom menu row. NSMenu sizes itself to its widest item,
    /// so these must agree or rows will not line up.
    static let menuWidth: CGFloat = 300
    /// Horizontal inset matching the system's own menu-item text alignment.
    static let hPad: CGFloat = 14

    // ── Panels ───────────────────────────────────────────────────────────────
    //
    // The card-on-a-menu look every section shares: a soft rounded surface
    // inset from the menu's edges, with content indented a further step — the
    // same arrangement System Settings uses for its group boxes. The status
    // card introduced it; the control sections reuse the exact same numbers so
    // the whole menu reads as one system.

    /// Margin between a panel's edge and the menu's.
    static let panelInset: CGFloat = 8
    /// Vertical breathing room inside a panel: the gap above the first piece
    /// of content and below the last. Every panel row applies it at both of
    /// its own edges, so a row junction inside a section reads as two of
    /// these — one uniform rhythm across the whole menu, status card included.
    static let panelPad: CGFloat = 8
    /// Horizontal breathing room inside a panel.
    static let panelContentPad: CGFloat = 12
    /// Left edge of anything drawn inside a panel.
    static let panelContentX = panelInset + panelContentPad
    static let panelRadius: CGFloat = 9
    static var panelColor: NSColor { NSColor.labelColor.withAlphaComponent(0.045) }

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
        let rMin: CGFloat = roundMinY ? panelRadius : 0
        let rMax: CGFloat = roundMaxY ? panelRadius : 0
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
    /// reads in plain black — a big green number looked like a status light,
    /// not a reading. The warning colours stay so heat still stands out.
    static func textHeatColor(_ celsius: Double?) -> NSColor {
        guard let celsius, celsius >= 60 else { return .labelColor }
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

    override func draw(_ dirtyRect: NSRect) {
        if let panelSegment {
            UIStyle.drawPanel(panelSegment, in: self)
        }
    }
}
