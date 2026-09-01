import AppKit

/// Auto-mode options: pick the Standard profile, or Custom with a user-chosen
/// engage temperature. Shown only while the cooling switch is on Auto.
///
/// Both profiles show a labelled **engage threshold** — the die temperature at
/// which the first cooling step kicks in — because that is the number that
/// explains the autopilot's behaviour, and leaving it implicit made the bare
/// slider read as an unlabelled setting. Only Custom gets the slider: Standard's
/// ladder is fixed, and its 40 °C engage point sits below the slider's own
/// minimum, so a disabled slider could not even be positioned honestly.
final class AutoOptionsView: PanelRowView {

    var onProfile: ((AutoProfile) -> Void)?
    /// Engage temperature in °C, fired continuously as the slider moves.
    var onEngageChange: ((Double) -> Void)?

    private(set) var profile: AutoProfile = .standard

    private let hPad = UIStyle.panelContentX
    private let segmented = NSSegmentedControl(labels: ["Standard", "Custom"],
                                               trackingMode: .selectOne,
                                               target: nil, action: nil)
    private let profileName = NSTextField(labelWithString: AutoProfile.standard.displayName)
    private let thresholdTitle = UIStyle.sectionLabel("ENGAGE THRESHOLD")
    private let descriptionLabel = NSTextField(
        labelWithString: "Cools automatically as your Mac heats up.")
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")

    /// Not flipped: y is measured from the bottom, as elsewhere in this view.
    /// The height leaves `UIStyle.panelPad` above the header, and the bottom
    /// row sits the same distance off the lower edge.
    private enum Layout {
        static let headerY: CGFloat = 88
        static let height: CGFloat = headerY + 13 + UIStyle.panelPad
        static let segmentedY: CGFloat = 56
        static let thresholdY: CGFloat = 34
        static let sliderY: CGFloat = UIStyle.panelPad
        static let descriptionY: CGFloat = UIStyle.panelPad
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))

        let header = UIStyle.sectionLabel("AUTO MODE")
        header.frame = NSRect(x: hPad, y: Layout.headerY, width: 150, height: 13)
        addSubview(header)

        profileName.font = UIStyle.captionFont
        profileName.textColor = .secondaryLabelColor
        profileName.alignment = .right
        profileName.frame = NSRect(x: width - hPad - 120, y: Layout.headerY,
                                   width: 120, height: 13)
        addSubview(profileName)

        segmented.segmentStyle = .rounded
        segmented.selectedSegment = 0
        segmented.target = self
        segmented.action = #selector(segmentChanged)
        segmented.frame = NSRect(x: hPad, y: Layout.segmentedY,
                                 width: width - hPad * 2, height: 24)
        segmented.autoresizingMask = .width
        addSubview(segmented)

        // The threshold row is always present, so the number that drives the
        // autopilot is never hidden behind a profile name.
        thresholdTitle.frame = NSRect(x: hPad, y: Layout.thresholdY, width: 160, height: 13)
        addSubview(thresholdTitle)

        valueLabel.font = UIStyle.valueFont
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - hPad - 80, y: Layout.thresholdY - 2,
                                  width: 80, height: 16)
        addSubview(valueLabel)

        // Standard and Custom share the bottom row: the description shows for
        // one, the slider for the other.
        descriptionLabel.font = UIStyle.captionFont
        descriptionLabel.textColor = .tertiaryLabelColor
        descriptionLabel.frame = NSRect(x: hPad, y: Layout.descriptionY,
                                        width: width - hPad * 2, height: 16)
        addSubview(descriptionLabel)

        slider.minValue = Config.Autopilot.customEngageMinC
        slider.maxValue = Config.Autopilot.customEngageMaxC
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.frame = NSRect(x: hPad, y: Layout.sliderY, width: width - hPad * 2, height: 20)
        slider.autoresizingMask = .width
        slider.isHidden = true
        addSubview(slider)
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
        updateValueLabel()
    }

    /// Standard's threshold is a fixed property of its ladder; Custom's is
    /// whatever the slider currently reads.
    private func updateValueLabel() {
        let celsius = (profile == .custom)
            ? slider.doubleValue
            : Config.Autopilot.standardEngageC
        valueLabel.stringValue = "≥ " + SystemInfo.formatTemp(celsius)
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
