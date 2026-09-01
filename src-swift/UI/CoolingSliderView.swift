import AppKit

/// The manual power slider: ten discrete steps across four labelled zones.
///
/// Mirrors the vendor app's layout — Off, then three sub-steps each within Low,
/// Medium and Max — so muscle memory carries over.
final class CoolingSliderView: NSView {

    /// One slider position: a TEC mode paired with a fan speed.
    ///
    /// Fan values are calibrated against an RPM probe rather than being linear
    /// percentages; the firmware's response curve is U-shaped, so e.g. 40 % and
    /// 70 % are ~6 200 and ~7 400 RPM. Changing a number here changes what the
    /// hardware actually does — see `docs/FINDINGS.md` before touching them.
    struct Step {
        let mode: CoolingMode
        let fanPercent: UInt8
        let name: String
    }

    static let steps: [Step] = [
        Step(mode: .off,    fanPercent:  0, name: "Off"),
        Step(mode: .low,    fanPercent: 40, name: "Low ·"),      // ~6 200 RPM
        Step(mode: .low,    fanPercent: 60, name: "Low ··"),     // ~6 600 RPM
        Step(mode: .low,    fanPercent: 70, name: "Low"),        // ~7 400 RPM
        Step(mode: .medium, fanPercent: 60, name: "Medium ·"),   // ~6 600 RPM
        Step(mode: .medium, fanPercent: 70, name: "Medium ··"),  // ~7 400 RPM
        Step(mode: .medium, fanPercent: 80, name: "Medium"),     // ~8 200 RPM
        Step(mode: .max,    fanPercent: 70, name: "Max ·"),      // ~7 400 RPM
        Step(mode: .max,    fanPercent: 75, name: "Max ··"),     // ~7 700 RPM
        Step(mode: .max,    fanPercent: 80, name: "Max"),        // ~8 200 RPM
    ]

    /// Step index chosen when the user switches into Manual with nothing (or
    /// Off) remembered — entering Manual should visibly do something.
    static let defaultStep = 6

    static var indexRange: ClosedRange<Int> { 0...(steps.count - 1) }

    /// Fires once, on mouse-up, with the chosen step index.
    var onStep: ((Int) -> Void)?

    private let slider = NSSlider()
    private let nameLabel = NSTextField(labelWithString: "Off")

    /// Wider than `UIStyle.hPad` so the slider's thumb doesn't overhang the row.
    private let hPad: CGFloat = 20
    private let zoneLabelY: CGFloat = 4

    init(width: CGFloat) {
        let height: CGFloat = 66
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let title = UIStyle.sectionLabel("POWER")
        title.frame = NSRect(x: UIStyle.hPad, y: height - 14, width: width * 0.6, height: 13)
        addSubview(title)

        nameLabel.font = UIStyle.captionFont
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .right
        nameLabel.frame = NSRect(x: 0, y: height - 14, width: width - UIStyle.hPad, height: 13)
        addSubview(nameLabel)

        slider.minValue = 0
        slider.maxValue = Double(Self.steps.count - 1)
        slider.numberOfTickMarks = Self.steps.count
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = true
        slider.integerValue = 0
        // Fire only on mouse-up. The thumb still tracks the drag, but we don't
        // write to the cooler until the user settles on a position — otherwise
        // a single drag would queue a dozen mode changes.
        slider.isContinuous = false
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.frame = NSRect(x: hPad, y: 18, width: width - hPad * 2, height: 30)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // ── Drawing ──────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Zone labels, centred under the tick marks that bound each zone.
        let zones: [(text: String, tick: Int, isMajor: Bool)] = [
            ("Off", 0, false), ("Low", 3, true), ("Med", 6, true), ("Max", 9, true),
        ]
        for zone in zones {
            let tick = convert(slider.rectOfTickMark(at: zone.tick), from: slider)
            let label = NSAttributedString(string: zone.text, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: zone.isMajor ? .semibold : .regular),
                .foregroundColor: zone.isMajor
                    ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
            ])
            label.draw(at: NSPoint(x: tick.midX - label.size().width / 2, y: zoneLabelY))
        }
    }

    // ── State ────────────────────────────────────────────────────────────────

    /// Moves the slider without firing `onStep`.
    func setStep(_ step: Int) {
        apply(step.clamped(to: Self.indexRange), notify: false)
    }

    func setEnabled(_ enabled: Bool) { slider.isEnabled = enabled }

    @objc private func sliderMoved() {
        apply(slider.integerValue, notify: true)
    }

    private func apply(_ step: Int, notify: Bool) {
        slider.integerValue = step
        nameLabel.stringValue = Self.steps[step].name
        if notify { onStep?(step) }
    }

    /// The step best matching a device state, for syncing the slider to values
    /// read back from the cooler.
    ///
    /// The device reports intermediate modes the slider has no position for, so
    /// the mode is first folded into its zone, then the closest fan speed within
    /// that zone wins.
    static func step(matching mode: CoolingMode, fanPercent: UInt8) -> Int {
        guard mode.isOn else { return 0 }
        let target = mode.zoneRepresentative
        return steps.enumerated()
            .filter { $0.element.mode == target }
            .min { a, b in
                abs(Int(a.element.fanPercent) - Int(fanPercent))
                    < abs(Int(b.element.fanPercent) - Int(fanPercent))
            }?.offset ?? 0
    }
}
