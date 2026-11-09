import AppKit

/// Auto-mode profile and engage threshold view.
final class AutoOptionsView: PanelRowView {

    var onEngageChange: ((Double) -> Void)?
    var onProfileChange: ((AutoProfile) -> Void)?

    private let hPad = UIStyle.panelContentX
    private let profileTitle = UIStyle.sectionLabel("SMART PROFILE")
    private let profileControl = NSSegmentedControl(labels: ["Balanced", "Smart Max"],
                                                    trackingMode: .selectOne,
                                                    target: nil, action: nil)
    private let captionLabel = NSTextField(wrappingLabelWithString: "")
    private let thresholdTitle = UIStyle.sectionLabel("ENGAGE THRESHOLD")
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")

    private enum Layout {
        static let sliderY: CGFloat = UIStyle.panelPad
        static let thresholdY: CGFloat = 34
        static let captionY: CGFloat = 58
        static let profileControlY: CGFloat = 90
        static let profileTitleY: CGFloat = 122
        static let height: CGFloat = 146
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))
        let contentWidth = width - hPad * 2

        captionLabel.font = UIStyle.captionFont
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.preferredMaxLayoutWidth = contentWidth
        captionLabel.translatesAutoresizingMaskIntoConstraints = true
        captionLabel.frame = NSRect(x: hPad, y: Layout.captionY, width: contentWidth, height: 28)
        addSubview(captionLabel)

        profileTitle.frame = NSRect(x: hPad, y: Layout.profileTitleY, width: contentWidth, height: 14)
        addSubview(profileTitle)

        profileControl.segmentStyle = .rounded
        profileControl.selectedSegment = 0
        profileControl.target = self
        profileControl.action = #selector(profileChanged)
        profileControl.frame = NSRect(x: hPad, y: Layout.profileControlY, width: contentWidth, height: 26)
        profileControl.autoresizingMask = .width
        addSubview(profileControl)

        thresholdTitle.frame = NSRect(x: hPad, y: Layout.thresholdY, width: 160, height: 14)
        addSubview(thresholdTitle)

        valueLabel.font = UIStyle.valueFont
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - hPad - 80, y: Layout.thresholdY - 1, width: 80, height: 16)
        addSubview(valueLabel)

        slider.minValue = Config.Autopilot.engageMinC
        slider.maxValue = Config.Autopilot.engageMaxC
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.frame = NSRect(x: hPad, y: Layout.sliderY, width: contentWidth, height: 20)
        slider.autoresizingMask = .width
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(engageC: Double, profile: AutoProfile) {
        let isInteracting = slider.cell?.isHighlighted == true || NSEvent.pressedMouseButtons != 0
        if !isInteracting && abs(slider.doubleValue - engageC) >= 0.5 {
            slider.doubleValue = engageC
            updateValueLabel()
        }
        profileControl.selectedSegment = (profile == .balanced) ? 0 : 1
        captionLabel.stringValue = profile.caption
    }

    func setEnabled(_ enabled: Bool) {
        let isInteracting = slider.cell?.isHighlighted == true || NSEvent.pressedMouseButtons != 0
        if !isInteracting {
            slider.isEnabled = enabled
        }
        profileControl.isEnabled = enabled
    }

    private func updateValueLabel() {
        let val = Int(round(slider.doubleValue))
        if val <= 38 {
            valueLabel.stringValue = "≥ 38°C (Min)"
        } else {
            valueLabel.stringValue = "≥ \(val)°C"
        }
    }

    @objc private func profileChanged() {
        let selected: AutoProfile = profileControl.selectedSegment == 0 ? .balanced : .smartMax
        captionLabel.stringValue = selected.caption
        onProfileChange?(selected)
    }

    @objc private func sliderMoved() {
        updateValueLabel()
        onEngageChange?(slider.doubleValue)
    }
}
