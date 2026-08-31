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

    // ── Fonts ────────────────────────────────────────────────────────────────

    static let sectionFont = NSFont.systemFont(ofSize: 9,  weight: .semibold)
    static let captionFont = NSFont.systemFont(ofSize: 10, weight: .regular)
    static let bodyFont    = NSFont.systemFont(ofSize: 11, weight: .regular)
    /// Monospaced digits stop telemetry values jittering as they update.
    static let valueFont   = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    // ── Helpers ──────────────────────────────────────────────────────────────

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
