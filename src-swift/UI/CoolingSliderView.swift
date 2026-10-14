import AppKit

/// The manual power slider: discrete steps across labelled zones.
///
/// Which steps there are, and what each one means, comes from the connected
/// model's profile (`DeviceProfile.manualSteps`); the 6 Pro mirrors the vendor
/// app's layout, so muscle memory carries over.
final class CoolingSliderView: PanelRowView {

    private(set) var steps = [ManualStep]()
    private var labels = [SliderLabel]()

    /// Fires once, on mouse-up, with the chosen step index.
    var onStep: ((Int) -> Void)?

    private let slider = DraggableSlider()
    private let nameLabel = NSTextField(labelWithString: "Off")

    /// Matches the panel content inset, which also keeps the slider's thumb
    /// from overhanging the panel edge.
    private let hPad: CGFloat = UIStyle.panelContentX
    private let zoneLabelY: CGFloat = UIStyle.panelPad

    init(width: CGFloat) {
        // panelPad + zone labels + slider + gap + header 13 + panelPad.
        let height: CGFloat = 76
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let titleY = height - UIStyle.panelPad - 13
        let title = UIStyle.sectionLabel("POWER")
        title.frame = NSRect(x: UIStyle.panelContentX, y: titleY, width: width * 0.6, height: 13)
        addSubview(title)

        nameLabel.font = UIStyle.captionFont
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .right
        nameLabel.frame = NSRect(x: 0, y: titleY, width: width - UIStyle.panelContentX, height: 13)
        addSubview(nameLabel)

        slider.minValue = 0
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
        for zone in labels where zone.tick < slider.numberOfTickMarks {
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

    /// Gives the slider the steps and labels of the connected model. Does
    /// nothing when they are unchanged, so it is cheap to call every refresh.
    func configure(steps newSteps: [ManualStep], labels newLabels: [SliderLabel]) {
        guard newSteps.map(\.name) != steps.map(\.name) else { return }
        steps = newSteps
        labels = newLabels
        slider.maxValue = Double(max(steps.count - 1, 1))
        slider.numberOfTickMarks = steps.count
        slider.integerValue = slider.integerValue.clamped(to: 0...max(steps.count - 1, 0))
        nameLabel.stringValue = steps.indices.contains(slider.integerValue)
            ? steps[slider.integerValue].name : ""
        needsDisplay = true
    }

    /// Moves the slider without firing `onStep`. Ignored while the user has hold of
    /// the thumb: a refresh triggered by the cooler's own telemetry would
    /// otherwise snap it back under their hand.
    func setStep(_ step: Int) {
        guard !steps.isEmpty, !slider.isDragging else { return }
        apply(step.clamped(to: 0...(steps.count - 1)), notify: false)
    }

    func setEnabled(_ enabled: Bool) { slider.isEnabled = enabled }

    @objc private func sliderMoved() {
        apply(slider.integerValue, notify: true)
    }

    private func apply(_ step: Int, notify: Bool) {
        slider.integerValue = step
        nameLabel.stringValue = steps[step].name
        if notify { onStep?(step) }
    }
}

/// An `NSSlider` that knows when it is being dragged. `mouseDown` runs the
/// tracking loop until the mouse is released, so the flag is true exactly for
/// the duration of a drag.
private final class DraggableSlider: NSSlider {
    private(set) var isDragging = false

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        super.mouseDown(with: event)
        isDragging = false
    }
}
