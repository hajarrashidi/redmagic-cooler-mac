import AppKit

/// Auto-mode engage threshold. Shown only while the connected cooler is in
/// Auto; this single slider replaces the old Standard/Custom profile choice.
final class AutoOptionsView: PanelRowView {

    /// Engage temperature in °C, fired continuously as the slider moves.
    var onEngageChange: ((Double) -> Void)?

    private let hPad = UIStyle.panelContentX
    private let thresholdTitle = UIStyle.sectionLabel("ENGAGE THRESHOLD")
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")

    /// Not flipped: y is measured from the bottom, as elsewhere in this view.
    /// The height leaves `UIStyle.panelPad` above the header, and the bottom
    /// row sits the same distance off the lower edge.
    private enum Layout {
        static let thresholdY: CGFloat = 34
        static let height: CGFloat = thresholdY + 13 + UIStyle.panelPad
        static let sliderY: CGFloat = UIStyle.panelPad
    }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Layout.height))

        thresholdTitle.frame = NSRect(x: hPad, y: Layout.thresholdY, width: 160, height: 13)
        addSubview(thresholdTitle)

        valueLabel.font = UIStyle.valueFont
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - hPad - 80, y: Layout.thresholdY - 2,
                                  width: 80, height: 16)
        addSubview(valueLabel)

        slider.minValue = Config.Autopilot.engageMinC
        slider.maxValue = Config.Autopilot.engageMaxC
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.frame = NSRect(x: hPad, y: Layout.sliderY, width: width - hPad * 2, height: 20)
        slider.autoresizingMask = .width
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// True while a custom curve sets the tier temperatures: the slider then has
    /// nothing to drive, so it is greyed and the row reports where cooling starts.
    private var usesCustomCurve = false

    /// Syncs the row to the app's current engage temperature, or, with a custom
    /// curve in use, to the temperature where its first tier engages.
    func configure(engageC: Double, customFirstC: Double? = nil) {
        usesCustomCurve = customFirstC != nil
        slider.doubleValue = engageC
        thresholdTitle.stringValue = usesCustomCurve ? "CUSTOM CURVE" : "ENGAGE THRESHOLD"
        valueLabel.stringValue = "≥ " + SystemInfo.formatTemp(customFirstC ?? engageC)
    }

    func setEnabled(_ enabled: Bool) {
        slider.isEnabled = enabled && !usesCustomCurve
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "≥ " + SystemInfo.formatTemp(slider.doubleValue)
    }

    @objc private func sliderMoved() {
        updateValueLabel()
        onEngageChange?(slider.doubleValue)
    }
}
