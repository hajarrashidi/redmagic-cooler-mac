import AppKit

/// Sleek, native 4-Stage Horizontal Pipeline for the Step-Ladder Autopilot Engine.
final class AutoOptionsView: PanelRowView {

    var onEngageChange: ((Double) -> Void)?
    var onShutoffChange: ((Double) -> Void)?
    var onMinFanChange: ((UInt8) -> Void)?
    var onProfileChange: ((AutoProfile) -> Void)?

    private let hPad = UIStyle.panelContentX
    private let titleLabel = UIStyle.sectionLabel("STEP-LADDER AUTOPILOT")
    private let activeTierBadge = NSTextField(labelWithString: "Standby")

    private struct StagePill {
        let box: NSBox
        let tempLabel: NSTextField
        let fanLabel: NSTextField
        let tier: CoolingTier
    }

    private var stagePills: [StagePill] = []
    private let safetyFootnote = NSTextField(labelWithString: "🛡️ Corte contra condensação < 36°C (retoma ≥ 38°C)")

    private enum Layout {
        static let pillHeight: CGFloat = 32
        static let pillGap: CGFloat = 6
        static let titleY: CGFloat = 58
        static let pillsY: CGFloat = 22
        static let footerY: CGFloat = 4
        static let height: CGFloat = 82
    }

    private static let milestones: [(tier: CoolingTier, temp: String, fan: String)] = [
        (.tier1_low,   "≥ 50°C", "40% Quiet"),
        (.tier2_med,   "≥ 60°C", "60% Med"),
        (.tier3_high,  "≥ 65°C", "80% Boost"),
        (.tier4_turbo, "≥ 70°C", "100% Max"),
    ]

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))
        let contentWidth = width - hPad * 2

        // Header
        titleLabel.frame = NSRect(x: hPad, y: Layout.titleY, width: 160, height: 14)
        addSubview(titleLabel)

        activeTierBadge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        activeTierBadge.textColor = .secondaryLabelColor
        activeTierBadge.alignment = .right
        activeTierBadge.frame = NSRect(x: width - hPad - 140, y: Layout.titleY - 1, width: 140, height: 16)
        addSubview(activeTierBadge)

        // Horizontal 4-Stage Pipeline
        let pillCount = CGFloat(Self.milestones.count)
        let totalGaps = Layout.pillGap * (pillCount - 1)
        let pillWidth = floor((contentWidth - totalGaps) / pillCount)

        for (index, item) in Self.milestones.enumerated() {
            let x = hPad + CGFloat(index) * (pillWidth + Layout.pillGap)
            let box = NSBox(frame: NSRect(x: x, y: Layout.pillsY, width: pillWidth, height: Layout.pillHeight))
            box.boxType = .custom
            box.borderWidth = 0
            box.cornerRadius = 6
            box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)

            let tLbl = NSTextField(labelWithString: item.temp)
            tLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            tLbl.textColor = .secondaryLabelColor
            tLbl.alignment = .center
            tLbl.frame = NSRect(x: 0, y: 15, width: pillWidth, height: 14)
            box.addSubview(tLbl)

            let fLbl = NSTextField(labelWithString: item.fan)
            fLbl.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
            fLbl.textColor = .tertiaryLabelColor
            fLbl.alignment = .center
            fLbl.frame = NSRect(x: 0, y: 3, width: pillWidth, height: 13)
            box.addSubview(fLbl)

            addSubview(box)
            stagePills.append(StagePill(box: box, tempLabel: tLbl, fanLabel: fLbl, tier: item.tier))
        }

        // Safety Footnote
        safetyFootnote.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        safetyFootnote.textColor = .secondaryLabelColor
        safetyFootnote.alignment = .center
        safetyFootnote.frame = NSRect(x: hPad, y: Layout.footerY, width: contentWidth, height: 14)
        addSubview(safetyFootnote)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Updates the pipeline visualizer to reflect current live engine state.
    func configure(currentTier: CoolingTier, dieTempC: Double?, isSafetyActive: Bool) {
        if isSafetyActive {
            activeTierBadge.stringValue = "🛡️ Cutoff (< 36°C)"
            activeTierBadge.textColor = .systemTeal
        } else if currentTier == .standby {
            activeTierBadge.stringValue = "Standby (< 50°C)"
            activeTierBadge.textColor = .secondaryLabelColor
        } else {
            activeTierBadge.stringValue = "\(currentTier.label)"
            activeTierBadge.textColor = .systemGreen
        }

        for pill in stagePills {
            let isActive = (!isSafetyActive && currentTier == pill.tier)
            if isActive {
                pill.box.fillColor = NSColor.systemGreen.withAlphaComponent(0.18)
                pill.tempLabel.textColor = .systemGreen
                pill.tempLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
                pill.fanLabel.textColor = .labelColor
                pill.fanLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            } else {
                pill.box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
                pill.tempLabel.textColor = .secondaryLabelColor
                pill.tempLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
                pill.fanLabel.textColor = .tertiaryLabelColor
                pill.fanLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
            }
        }
    }

    /// Compatibility overload.
    func configure(engageC: Double, shutoffC: Double, minFanPercent: UInt8, profile: AutoProfile) {}

    func setEnabled(_ enabled: Bool) {
        alphaValue = enabled ? 1.0 : 0.6
    }
}
