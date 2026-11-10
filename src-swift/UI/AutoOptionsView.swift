import AppKit

/// Continuous 4-Stage Performance Ladder for Autopilot Cooling.
///
/// Implements Emil Kowalski & Apple HIG design standards:
/// - Single continuous track without bulky box-in-box nesting
/// - Vibrant active capsule highlight with glowing status dot
/// - Crisp, readable typography without AI-slop explanatory captions
final class AutoOptionsView: PanelRowView {

    var onEngageChange: ((Double) -> Void)?
    var onShutoffChange: ((Double) -> Void)?
    var onMinFanChange: ((UInt8) -> Void)?
    var onProfileChange: ((AutoProfile) -> Void)?

    private struct Milestone {
        let tier: CoolingTier
        let tempText: String
        let fanText: String
    }

    private static let milestones: [Milestone] = [
        Milestone(tier: .tier1_low,   tempText: "≥ 50°", fanText: "40% Quiet"),
        Milestone(tier: .tier2_med,   tempText: "≥ 60°", fanText: "60% Med"),
        Milestone(tier: .tier3_high,  tempText: "≥ 65°", fanText: "80% Boost"),
        Milestone(tier: .tier4_turbo, tempText: "≥ 70°", fanText: "100% Max"),
    ]

    private var currentTier: CoolingTier = .standby
    private var isSafetyActive: Bool = false

    private static let pad = UIStyle.panelContentX
    private static let trackHeight: CGFloat = 36
    private static let trackY: CGFloat = 8
    private static let footerY: CGFloat = 48
    static let height: CGFloat = 68

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = .width
        panelSegment = .bottom
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(currentTier: CoolingTier, dieTempC: Double?, isSafetyActive: Bool) {
        if self.currentTier != currentTier || self.isSafetyActive != isSafetyActive {
            self.currentTier = currentTier
            self.isSafetyActive = isSafetyActive
            needsDisplay = true
        }
    }

    func configure(engageC: Double, shutoffC: Double, minFanPercent: UInt8, profile: AutoProfile) {}

    func setEnabled(_ enabled: Bool) {
        alphaValue = enabled ? 1.0 : 0.6
    }

    // ── Drawing ──────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = Self.pad
        let contentWidth = bounds.width - pad * 2
        let count = CGFloat(Self.milestones.count)
        let segmentWidth = floor(contentWidth / count)

        // 1. Unified Background Track
        let trackRect = NSRect(x: pad, y: Self.trackY, width: contentWidth, height: Self.trackHeight)
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 7, yRadius: 7).fill()

        // 2. Draw Segments and Active Pill
        for (index, item) in Self.milestones.enumerated() {
            let x = pad + CGFloat(index) * segmentWidth
            let segRect = NSRect(x: x, y: Self.trackY, width: segmentWidth, height: Self.trackHeight)
            let isActive = (!isSafetyActive && currentTier == item.tier)

            if isActive {
                let pillRect = segRect.insetBy(dx: 2, dy: 2)
                NSColor.systemGreen.withAlphaComponent(0.18).setFill()
                let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 5.5, yRadius: 5.5)
                pillPath.fill()
                NSColor.systemGreen.withAlphaComponent(0.35).setStroke()
                pillPath.lineWidth = 1
                pillPath.stroke()

                // Active dot and labels
                let dotAttr = UIStyle.text("●", NSFont.systemFont(ofSize: 6, weight: .bold), .systemGreen)
                dotAttr.draw(at: NSPoint(x: pillRect.minX + 4, y: Self.trackY + 7))

                let tempAttr = UIStyle.text(item.tempText, NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold), .systemGreen)
                let tempX = segRect.midX - tempAttr.size().width / 2
                tempAttr.draw(at: NSPoint(x: tempX, y: Self.trackY + 4))

                let fanAttr = UIStyle.text(item.fanText, NSFont.systemFont(ofSize: 9.5, weight: .semibold), .labelColor)
                let fanX = segRect.midX - fanAttr.size().width / 2
                fanAttr.draw(at: NSPoint(x: fanX, y: Self.trackY + 18))
            } else {
                // Inactive labels
                let tempAttr = UIStyle.text(item.tempText, NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium), .secondaryLabelColor)
                let tempX = segRect.midX - tempAttr.size().width / 2
                tempAttr.draw(at: NSPoint(x: tempX, y: Self.trackY + 5))

                let fanAttr = UIStyle.text(item.fanText, NSFont.systemFont(ofSize: 9, weight: .regular), .tertiaryLabelColor)
                let fanX = segRect.midX - fanAttr.size().width / 2
                fanAttr.draw(at: NSPoint(x: fanX, y: Self.trackY + 19))

                // Divider line after segment (except last)
                if index < Self.milestones.count - 1 {
                    let divX = x + segmentWidth
                    let divRect = NSRect(x: divX, y: Self.trackY + 6, width: 1, height: Self.trackHeight - 12)
                    NSColor.separatorColor.withAlphaComponent(0.12).setFill()
                    divRect.fill()
                }
            }
        }

        // 3. Footer Safety Caption
        let footerText = "🛡️ Proteção contra condensação: corte < 36°C · retoma ≥ 38°C"
        let footerAttr = UIStyle.text(footerText, NSFont.systemFont(ofSize: 9.5, weight: .medium), .secondaryLabelColor)
        let footerX = bounds.midX - footerAttr.size().width / 2
        footerAttr.draw(at: NSPoint(x: footerX, y: Self.footerY))
    }
}
