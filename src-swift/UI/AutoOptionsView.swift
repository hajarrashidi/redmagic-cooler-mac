import AppKit

/// Auto-mode profile, engage threshold, shutoff cutoff, and base minimum power controls.
final class AutoOptionsView: PanelRowView {

    var onEngageChange: ((Double) -> Void)?
    var onShutoffChange: ((Double) -> Void)?
    var onMinFanChange: ((UInt8) -> Void)?
    var onProfileChange: ((AutoProfile) -> Void)?

    private let hPad = UIStyle.panelContentX
    private let profileTitle = UIStyle.sectionLabel("SMART PROFILE")
    private let profileControl = NSSegmentedControl(labels: ["Balanced", "Smart Max"],
                                                    trackingMode: .selectOne,
                                                    target: nil, action: nil)
    private let captionLabel = NSTextField(wrappingLabelWithString: "")

    // ── Engage Threshold ──
    private let engageTitle = UIStyle.sectionLabel("ENGAGE THRESHOLD")
    private let engageSlider = NSSlider()
    private let engageValueLabel = NSTextField(labelWithString: "")

    // ── Shutoff Threshold ──
    private let shutoffTitle = UIStyle.sectionLabel("SHUTOFF THRESHOLD")
    private let shutoffSlider = NSSlider()
    private let shutoffValueLabel = NSTextField(labelWithString: "")

    // ── Base Minimum Power ──
    private let minPowerTitle = UIStyle.sectionLabel("MIN POWER")
    private let minPowerControl = NSSegmentedControl(labels: ["40%", "50%", "60%", "75%"],
                                                     trackingMode: .selectOne,
                                                     target: nil, action: nil)

    private enum Layout {
        static let minPowerControlY: CGFloat = 10
        static let minPowerTitleY: CGFloat = 38
        static let shutoffSliderY: CGFloat = 58
        static let shutoffTitleY: CGFloat = 82
        static let engageSliderY: CGFloat = 104
        static let engageTitleY: CGFloat = 128
        static let captionY: CGFloat = 150
        static let profileControlY: CGFloat = 182
        static let profileTitleY: CGFloat = 212
        static let height: CGFloat = 236
    }

    private static let minFanOptions: [UInt8] = [40, 50, 60, 75]

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))
        let contentWidth = width - hPad * 2

        // Profile Title & Control
        profileTitle.frame = NSRect(x: hPad, y: Layout.profileTitleY, width: contentWidth, height: 14)
        addSubview(profileTitle)

        profileControl.segmentStyle = .rounded
        profileControl.selectedSegment = 0
        profileControl.target = self
        profileControl.action = #selector(profileChanged)
        profileControl.frame = NSRect(x: hPad, y: Layout.profileControlY, width: contentWidth, height: 26)
        profileControl.autoresizingMask = .width
        addSubview(profileControl)

        captionLabel.font = UIStyle.captionFont
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.preferredMaxLayoutWidth = contentWidth
        captionLabel.frame = NSRect(x: hPad, y: Layout.captionY, width: contentWidth, height: 26)
        addSubview(captionLabel)

        // Engage Threshold
        engageTitle.frame = NSRect(x: hPad, y: Layout.engageTitleY, width: 160, height: 14)
        addSubview(engageTitle)

        engageValueLabel.font = UIStyle.valueFont
        engageValueLabel.alignment = .right
        engageValueLabel.frame = NSRect(x: width - hPad - 90, y: Layout.engageTitleY - 1, width: 90, height: 16)
        addSubview(engageValueLabel)

        engageSlider.minValue = Config.Autopilot.tempMinC
        engageSlider.maxValue = Config.Autopilot.tempMaxC
        engageSlider.isContinuous = true
        engageSlider.target = self
        engageSlider.action = #selector(engageSliderMoved)
        engageSlider.frame = NSRect(x: hPad, y: Layout.engageSliderY, width: contentWidth, height: 20)
        engageSlider.autoresizingMask = .width
        addSubview(engageSlider)

        // Shutoff Threshold
        shutoffTitle.frame = NSRect(x: hPad, y: Layout.shutoffTitleY, width: 160, height: 14)
        addSubview(shutoffTitle)

        shutoffValueLabel.font = UIStyle.valueFont
        shutoffValueLabel.alignment = .right
        shutoffValueLabel.frame = NSRect(x: width - hPad - 110, y: Layout.shutoffTitleY - 1, width: 110, height: 16)
        addSubview(shutoffValueLabel)

        shutoffSlider.minValue = Config.Autopilot.tempMinC
        shutoffSlider.maxValue = Config.Autopilot.tempMaxC
        shutoffSlider.isContinuous = true
        shutoffSlider.target = self
        shutoffSlider.action = #selector(shutoffSliderMoved)
        shutoffSlider.frame = NSRect(x: hPad, y: Layout.shutoffSliderY, width: contentWidth, height: 20)
        shutoffSlider.autoresizingMask = .width
        addSubview(shutoffSlider)

        // Min Power Selector (Available for both Balanced and Smart Max)
        minPowerTitle.frame = NSRect(x: hPad, y: Layout.minPowerTitleY, width: contentWidth, height: 14)
        addSubview(minPowerTitle)

        minPowerControl.segmentStyle = .rounded
        minPowerControl.selectedSegment = 0 // 40% default (quiet hardware floor)
        minPowerControl.target = self
        minPowerControl.action = #selector(minPowerChanged)
        minPowerControl.frame = NSRect(x: hPad, y: Layout.minPowerControlY, width: contentWidth, height: 24)
        minPowerControl.autoresizingMask = .width
        addSubview(minPowerControl)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(engageC: Double, shutoffC: Double, minFanPercent: UInt8, profile: AutoProfile) {
        let isUserInteracting = NSEvent.pressedMouseButtons != 0
                             || engageSlider.cell?.isHighlighted == true
                             || shutoffSlider.cell?.isHighlighted == true

        if !isUserInteracting {
            if abs(engageSlider.doubleValue - engageC) >= 0.5 {
                engageSlider.doubleValue = engageC
                updateEngageLabel()
            }
            if abs(shutoffSlider.doubleValue - shutoffC) >= 0.5 {
                shutoffSlider.doubleValue = shutoffC
                updateShutoffLabel()
            }
        }

        profileControl.selectedSegment = (profile == .balanced) ? 0 : 1
        captionLabel.stringValue = profile.caption

        // Match closest minFanPercent in segmented control
        let targetIndex = Self.minFanOptions.enumerated().min(by: {
            abs(Int($0.element) - Int(minFanPercent)) < abs(Int($1.element) - Int(minFanPercent))
        })?.offset ?? 0
        minPowerControl.selectedSegment = targetIndex

        // Min power is fully active and enabled for both Balanced and Smart Max!
        minPowerControl.isEnabled = true
        minPowerTitle.alphaValue = 1.0
    }

    func setEnabled(_ enabled: Bool) {
        let isUserInteracting = NSEvent.pressedMouseButtons != 0
                             || engageSlider.cell?.isHighlighted == true
                             || shutoffSlider.cell?.isHighlighted == true

        if !isUserInteracting {
            engageSlider.isEnabled = enabled
            shutoffSlider.isEnabled = enabled
        }
        profileControl.isEnabled = enabled
        minPowerControl.isEnabled = enabled
    }

    private func updateEngageLabel() {
        let val = Int(round(engageSlider.doubleValue))
        engageValueLabel.stringValue = "≥ \(val)°C"
    }

    private func updateShutoffLabel() {
        let val = Int(round(shutoffSlider.doubleValue))
        shutoffValueLabel.stringValue = "< \(val)°C (Off)"
    }

    @objc private func profileChanged() {
        let selected: AutoProfile = profileControl.selectedSegment == 0 ? .balanced : .smartMax
        captionLabel.stringValue = selected.caption
        onProfileChange?(selected)
    }

    @objc private func engageSliderMoved() {
        let rawVal = round(engageSlider.doubleValue)
        let safeEngage = rawVal.clamped(to: Config.Autopilot.engageMinC...Config.Autopilot.engageMaxC)
        engageSlider.doubleValue = safeEngage
        updateEngageLabel()

        // If engage is dragged down towards shutoff, push shutoff downward so it never blocks or locks up
        if shutoffSlider.doubleValue > safeEngage - 2.0 {
            let newShutoff = max(Config.Autopilot.shutoffMinC, safeEngage - 2.0)
            shutoffSlider.doubleValue = newShutoff
            updateShutoffLabel()
            onShutoffChange?(newShutoff)
        }

        onEngageChange?(safeEngage)
    }

    @objc private func shutoffSliderMoved() {
        let rawVal = round(shutoffSlider.doubleValue)
        let safeShutoff = rawVal.clamped(to: Config.Autopilot.shutoffMinC...Config.Autopilot.shutoffMaxC)
        shutoffSlider.doubleValue = safeShutoff
        updateShutoffLabel()

        // If shutoff is dragged up towards engage, push engage upward so it never blocks or locks up
        if engageSlider.doubleValue < safeShutoff + 2.0 {
            let newEngage = min(Config.Autopilot.engageMaxC, safeShutoff + 2.0)
            engageSlider.doubleValue = newEngage
            updateEngageLabel()
            onEngageChange?(newEngage)
        }

        onShutoffChange?(safeShutoff)
    }

    @objc private func minPowerChanged() {
        let idx = minPowerControl.selectedSegment
        guard idx >= 0 && idx < Self.minFanOptions.count else { return }
        let selectedPercent = Self.minFanOptions[idx]
        onMinFanChange?(selectedPercent)
    }
}
