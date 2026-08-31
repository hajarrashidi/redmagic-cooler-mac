import AppKit

/// Auto-mode options: pick the Standard profile, or Custom with a user-chosen
/// engage temperature. Shown only while the cooling switch is on Auto.
final class AutoOptionsView: NSView {

    var onProfile: ((AutoProfile) -> Void)?
    /// Engage temperature in °C, fired continuously as the slider moves.
    var onEngageChange: ((Double) -> Void)?

    private(set) var profile: AutoProfile = .standard

    private let hPad = UIStyle.hPad
    private let segmented = NSSegmentedControl(labels: ["Standard", "Custom"],
                                               trackingMode: .selectOne,
                                               target: nil, action: nil)
    private let profileName = NSTextField(labelWithString: AutoProfile.standard.displayName)
    private let descriptionLabel = NSTextField(
        labelWithString: "Cools automatically as your Mac heats up.")
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 80))

        let header = NSTextField(labelWithString: "AUTO MODE")
        header.font = UIStyle.sectionFont
        header.textColor = .tertiaryLabelColor
        header.frame = NSRect(x: hPad, y: 64, width: 150, height: 13)
        addSubview(header)

        profileName.font = UIStyle.captionFont
        profileName.textColor = .secondaryLabelColor
        profileName.alignment = .right
        profileName.frame = NSRect(x: width - hPad - 120, y: 64, width: 120, height: 13)
        addSubview(profileName)

        segmented.segmentStyle = .rounded
        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(segmentChanged)
        segmented.frame = NSRect(x: hPad, y: 34, width: width - hPad * 2, height: 24)
        segmented.autoresizingMask = .width
        addSubview(segmented)

        // Standard and Custom share this row: the description shows for one,
        // the slider and its readout for the other.
        descriptionLabel.font = UIStyle.captionFont
        descriptionLabel.textColor = .tertiaryLabelColor
        descriptionLabel.frame = NSRect(x: hPad, y: 8, width: width - hPad * 2, height: 16)
        addSubview(descriptionLabel)

        slider.minValue = Config.Autopilot.customEngageMinC
        slider.maxValue = Config.Autopilot.customEngageMaxC
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.frame = NSRect(x: hPad, y: 6, width: width - hPad * 2 - 60, height: 20)
        slider.autoresizingMask = .width
        slider.isHidden = true
        addSubview(slider)

        valueLabel.font = UIStyle.valueFont
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - hPad - 56, y: 6, width: 56, height: 16)
        valueLabel.isHidden = true
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Syncs the row to the app's current profile and engage temperature.
    func configure(profile: AutoProfile, engageC: Double) {
        self.profile = profile
        segmented.selectedSegment = (profile == .custom) ? 1 : 0
        slider.doubleValue = engageC
        updateForProfile()
    }

    func setEnabled(_ enabled: Bool) {
        segmented.isEnabled = enabled
        slider.isEnabled = enabled
    }

    private func updateForProfile() {
        let isCustom = (profile == .custom)
        profileName.stringValue = profile.displayName
        descriptionLabel.isHidden = isCustom
        slider.isHidden = !isCustom
        valueLabel.isHidden = !isCustom
        if isCustom { updateValueLabel() }
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "≥ " + SystemInfo.formatTemp(slider.doubleValue)
    }

    @objc private func segmentChanged() {
        profile = (segmented.selectedSegment == 1) ? .custom : .standard
        updateForProfile()
        onProfile?(profile)
    }

    @objc private func sliderMoved() {
        updateValueLabel()
        onEngageChange?(slider.doubleValue)
    }
}
