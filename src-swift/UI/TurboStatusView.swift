import AppKit

/// Dedicated Turbo Status Banner shown when Turbo mode is engaged.
///
/// Replaces the empty gap with a bold, clear confirmation of maximum cooling power
/// and active condensation protection.
final class TurboStatusView: PanelRowView {

    static let height: CGFloat = 60
    private static let pad = UIStyle.panelContentX

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = .width
        panelSegment = .bottom
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = Self.pad
        let contentWidth = bounds.width - pad * 2

        // Card container
        let cardRect = NSRect(x: pad, y: 6, width: contentWidth, height: Self.height - 12)
        NSColor.systemRed.withAlphaComponent(0.08).setFill()
        let path = NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7)
        path.fill()
        NSColor.systemRed.withAlphaComponent(0.20).setStroke()
        path.lineWidth = 1
        path.stroke()

        // 1. Title
        let titleAttr = UIStyle.text("⚡ Turbo Boost 100% (Potência Máxima)",
                                     NSFont.systemFont(ofSize: 11, weight: .semibold),
                                     .systemRed)
        titleAttr.draw(at: NSPoint(x: pad + 10, y: 12))

        // 2. Subtitle
        let subAttr = UIStyle.text("Ventoinha a ~10.000 RPM · Resfriamento ininterrupto",
                                   NSFont.systemFont(ofSize: 9.5, weight: .regular),
                                   .secondaryLabelColor)
        subAttr.draw(at: NSPoint(x: pad + 10, y: 28))

        // 3. Safety note
        let safeAttr = UIStyle.text("🛡️ Proteção ativa: desliga automaticamente se Mac < 36°C",
                                    NSFont.systemFont(ofSize: 9, weight: .medium),
                                    .tertiaryLabelColor)
        safeAttr.draw(at: NSPoint(x: pad + 10, y: 42))
    }
}
