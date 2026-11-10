import AppKit

/// Visualizer for the Deterministic 4-Stage Step-Ladder Autopilot Engine.
final class AutoOptionsView: PanelRowView {

    var onEngageChange: ((Double) -> Void)?
    var onShutoffChange: ((Double) -> Void)?
    var onMinFanChange: ((UInt8) -> Void)?
    var onProfileChange: ((AutoProfile) -> Void)?

    private let hPad = UIStyle.panelContentX
    private let titleLabel = UIStyle.sectionLabel("AUTOPILOT STEP-LADDER")
    private let activeTierBadge = NSTextField(labelWithString: "Standby")

    // Tier Display Labels
    private struct TierRowViews {
        let container: NSBox
        let tierLabel: NSTextField
        let tempLabel: NSTextField
        let powerLabel: NSTextField
        let bufferLabel: NSTextField
    }

    private var tierViews: [TierRowViews] = []
    private let safetyFootnote = NSTextField(labelWithString: "🛡️ Safety Cutoff: < 36°C (Re-arms ≥ 38°C) · 20s Dwell Buffer")

    private enum Layout {
        static let rowHeight: CGFloat = 22
        static let rowGap: CGFloat = 4
        static let titleY: CGFloat = 142
        static let firstRowY: CGFloat = 114
        static let footerY: CGFloat = 8
        static let height: CGFloat = 166
    }

    private static let tierSpecs: [(tier: CoolingTier, name: String, trigger: String, power: String, buffer: String)] = [
        (.tier1_low,   "Tier 1", "≥ 50°C", "40% Quiet",   "Release < 42°C"),
        (.tier2_med,   "Tier 2", "≥ 60°C", "60% Medium",  "Release < 55°C"),
        (.tier3_high,  "Tier 3", "≥ 65°C", "80% Boost",   "Release < 61°C"),
        (.tier4_turbo, "Tier 4", "≥ 70°C", "100% Turbo",  "Release < 66°C"),
    ]

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))
        let contentWidth = width - hPad * 2

        // Header
        titleLabel.frame = NSRect(x: hPad, y: Layout.titleY, width: 170, height: 14)
        addSubview(titleLabel)

        activeTierBadge.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        activeTierBadge.textColor = .secondaryLabelColor
        activeTierBadge.alignment = .right
        activeTierBadge.frame = NSRect(x: width - hPad - 150, y: Layout.titleY - 1, width: 150, height: 16)
        addSubview(activeTierBadge)

        // 4-Stage Tier Rows
        var currentY = Layout.firstRowY
        for spec in Self.tierSpecs {
            let box = NSBox(frame: NSRect(x: hPad, y: currentY, width: contentWidth, height: Layout.rowHeight))
            box.boxType = .custom
            box.borderWidth = 0
            box.cornerRadius = 5
            box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)

            let tLbl = NSTextField(labelWithString: spec.name)
            tLbl.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            tLbl.textColor = .labelColor
            tLbl.frame = NSRect(x: 8, y: 3, width: 48, height: 16)
            box.addSubview(tLbl)

            let trigLbl = NSTextField(labelWithString: spec.trigger)
            trigLbl.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            trigLbl.textColor = .systemBlue
            trigLbl.frame = NSRect(x: 58, y: 3, width: 55, height: 16)
            box.addSubview(trigLbl)

            let pwrLbl = NSTextField(labelWithString: spec.power)
            pwrLbl.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            pwrLbl.textColor = .labelColor
            pwrLbl.frame = NSRect(x: 115, y: 3, width: 75, height: 16)
            box.addSubview(pwrLbl)

            let bufLbl = NSTextField(labelWithString: spec.buffer)
            bufLbl.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            bufLbl.textColor = .secondaryLabelColor
            bufLbl.alignment = .right
            bufLbl.frame = NSRect(x: contentWidth - 100, y: 3, width: 92, height: 16)
            box.addSubview(bufLbl)

            addSubview(box)
            tierViews.append(TierRowViews(container: box, tierLabel: tLbl, tempLabel: trigLbl, powerLabel: pwrLbl, bufferLabel: bufLbl))

            currentY -= (Layout.rowHeight + Layout.rowGap)
        }

        // Safety Footnote
        safetyFootnote.font = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        safetyFootnote.textColor = .tertiaryLabelColor
        safetyFootnote.alignment = .center
        safetyFootnote.frame = NSRect(x: hPad, y: Layout.footerY, width: contentWidth, height: 14)
        addSubview(safetyFootnote)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Primary configuration call updating the visualizer to reflect current live engine state.
    func configure(currentTier: CoolingTier, dieTempC: Double?, isSafetyActive: Bool) {
        if isSafetyActive {
            activeTierBadge.stringValue = "🛡️ Cutoff Active (< 36°C)"
            activeTierBadge.textColor = .systemTeal
        } else if currentTier == .standby {
            activeTierBadge.stringValue = "Standby (Idle < 50°C)"
            activeTierBadge.textColor = .secondaryLabelColor
        } else {
            activeTierBadge.stringValue = "\(currentTier.label)"
            activeTierBadge.textColor = .systemGreen
        }

        for (index, spec) in Self.tierSpecs.enumerated() {
            guard index < tierViews.count else { continue }
            let views = tierViews[index]
            let isActive = (!isSafetyActive && currentTier == spec.tier)

            if isActive {
                views.container.fillColor = NSColor.systemGreen.withAlphaComponent(0.18)
                views.tierLabel.textColor = .systemGreen
                views.tempLabel.textColor = .systemGreen
                views.powerLabel.textColor = .labelColor
                views.bufferLabel.textColor = .labelColor
            } else {
                views.container.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
                views.tierLabel.textColor = .secondaryLabelColor
                views.tempLabel.textColor = .systemBlue
                views.powerLabel.textColor = .secondaryLabelColor
                views.bufferLabel.textColor = .tertiaryLabelColor
            }
        }
    }

    /// Compatibility overload for callers passing engage/shutoff/profile.
    func configure(engageC: Double, shutoffC: Double, minFanPercent: UInt8, profile: AutoProfile) {
        // Safe no-op or default configuration for backwards compatibility
    }

    func setEnabled(_ enabled: Bool) {
        alphaValue = enabled ? 1.0 : 0.6
    }
}
