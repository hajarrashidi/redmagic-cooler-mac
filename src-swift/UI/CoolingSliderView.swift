import AppKit

/// The manual power slider: ten discrete steps across four labelled zones.
///
/// Mirrors the vendor app's layout — Off, then three sub-steps each within Low,
/// Medium and Max — so muscle memory carries over.
final class CoolingSliderView: PanelRowView {

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
        Step(mode: .off,    fanPercent:   0, name: "Off"),
        Step(mode: .low,    fanPercent:  40, name: "Low ·"),      // ~6 200 RPM
        Step(mode: .low,    fanPercent:  50, name: "Low ··"),     // ~6 600 RPM
        Step(mode: .low,    fanPercent:  60, name: "Low"),        // ~7 200 RPM
        Step(mode: .medium, fanPercent:  65, name: "Med ·"),      // ~7 600 RPM
        Step(mode: .medium, fanPercent:  75, name: "Med ··"),     // ~8 000 RPM
        Step(mode: .medium, fanPercent:  80, name: "Med"),        // ~8 400 RPM
        Step(mode: .max,    fanPercent:  85, name: "Max ·"),      // ~8 800 RPM
        Step(mode: .max,    fanPercent:  95, name: "Max ··"),     // ~9 400 RPM
        Step(mode: .max,    fanPercent: 100, name: "Max"),        // ~10 000 RPM (Full 100% Boost)
    ]

    /// Step index chosen when the user switches into Manual with nothing (or
    /// Off) remembered — entering Manual should visibly do something.
    static let defaultStep = 6

    static var indexRange: ClosedRange<Int> { 0...(steps.count - 1) }

    /// Fires once, on mouse-up, with the chosen step index.
    var onStep: ((Int) -> Void)?

    private let slider = NSSlider()
    private let nameLabel = NSTextField(labelWithString: "Off")

    /// Matches the panel content inset, which also keeps the slider's thumb
    /// from overhanging the panel edge.
    private let hPad: CGFloat = UIStyle.panelContentX
    private let zoneLabelY: CGFloat = UIStyle.panelPad

    init(width: CGFloat) {
        // panelPad + zone labels + slider + gap + header 13 + panelPad.
        let height: CGFloat = 76
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let titleY = height - UIStyle.panelPad - 14
        let title = UIStyle.sectionLabel("Fan Power")
        title.frame = NSRect(x: UIStyle.panelContentX, y: titleY, width: width * 0.5, height: 14)
        addSubview(title)

        nameLabel.font = UIStyle.valueFont
        nameLabel.textColor = .labelColor
        nameLabel.alignment = .right
        nameLabel.frame = NSRect(x: 0, y: titleY, width: width - UIStyle.panelContentX, height: 14)
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
        slider.frame = NSRect(x: hPad, y: 22, width: width - hPad * 2, height: 30)
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
    /// Matches by fan speed across active steps (1..<steps.count), ensuring accurate
    /// representation even on devices with binary mode switches (like REDMAGIC 5 Pro).
    static func step(matching mode: CoolingMode, fanPercent: UInt8) -> Int {
        guard mode.isOn && fanPercent > 0 else { return 0 }
        let activeSteps = Array(steps.enumerated().dropFirst())
        return activeSteps.min { a, b in
            abs(Int(a.element.fanPercent) - Int(fanPercent))
                < abs(Int(b.element.fanPercent) - Int(fanPercent))
        }?.offset ?? 1
    }
}
