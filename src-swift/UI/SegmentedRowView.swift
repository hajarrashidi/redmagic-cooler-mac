import AppKit

/// A labelled segmented control laid out as a menu row.
///
/// Three rows in this menu — cooling mode, LED effect, breath
/// style — were near-identical copies of the same 25 lines of framing code.
/// This is that layout, once. Subclasses supply their own typed API on top.
class SegmentedRowView: PanelRowView {

    /// 8 + control 26 + 8 — panelPad at both edges. A row with an inline title
    /// or a caption is taller by exactly what those need.
    static let rowHeight: CGFloat = 60

    let control: NSSegmentedControl
    private let captionLabel = NSTextField(wrappingLabelWithString: "")

    /// - Parameters:
    ///   - title: uppercase label drawn above the control. `nil` for a row
    ///     whose section header is a menu row of its own, outside the panel.
    ///   - labels: segment titles, in order.
    ///   - captions: every sentence this row might show, for a choice whose
    ///     segment labels can't carry their own meaning. The row is sized for
    ///     the tallest of them and shows one at a time — a caption that
    ///     resized the row would need `NSMenu` to re-lay out an open menu,
    ///     which it does not do.
    init(width: CGFloat, title: String?, labels: [String], captions: [String] = []) {
        control = NSSegmentedControl(labels: labels,
                                     trackingMode: .selectOne,
                                     target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))

        let hPad = UIStyle.panelContentX
        let content = width - hPad * 2

        // Built bottom-up: this view is unflipped, and a caption's height is
        // only known once it has wrapped, so everything above it follows from
        // where it lands rather than from a constant.
        control.segmentStyle = .rounded
        control.selectedSegment = 0
        control.target = self
        control.action = #selector(segmentChanged)
        control.frame = NSRect(x: hPad, y: UIStyle.panelPad,
                               width: content, height: 26)
        control.autoresizingMask = .width
        addSubview(control)

        var top = UIStyle.panelPad + 26

        if !captions.isEmpty {
            captionLabel.font = UIStyle.captionFont
            captionLabel.textColor = .secondaryLabelColor
            captionLabel.preferredMaxLayoutWidth = content
            // `wrappingLabelWithString` hands back an Auto Layout field; every
            // row here is placed by frame, and a constraint-driven label with
            // no constraints collapses to nothing.
            captionLabel.translatesAutoresizingMaskIntoConstraints = true
            let height = captions.map { text -> CGFloat in
                captionLabel.stringValue = text
                return ceil(captionLabel.fittingSize.height)
            }.max() ?? 0
            captionLabel.stringValue = captions[0]
            top += 6
            captionLabel.frame = NSRect(x: hPad, y: top, width: content, height: height)
            addSubview(captionLabel)
            top += height
        }

        if let title {
            top += 5
            frame.size.height = top + 13 + UIStyle.panelPad
            let header = UIStyle.sectionLabel(title)
            header.frame = NSRect(x: hPad, y: frame.height - UIStyle.panelPad - 13,
                                  width: content, height: 13)
            addSubview(header)
        } else {
            frame.size.height = top + UIStyle.panelPad
        }
    }

    /// Swaps the visible caption. Only ever one of the strings the row was
    /// sized for, so the frame never has to move.
    func setCaption(_ text: String) {
        guard captionLabel.stringValue != text else { return }
        captionLabel.stringValue = text
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Greys the control out while a change is in flight.
    func setEnabled(_ enabled: Bool) { control.isEnabled = enabled }

    /// Overridden by subclasses to publish their typed selection.
    @objc func segmentChanged() {}
}

/// Auto / Manual / Turbo — chooses which control loop owns the cooler.
final class ModeSwitchView: SegmentedRowView {

    var onSelect: ((AppMode) -> Void)?

    private static let autoCaption =
        "Deterministic 4-stage cooling (50°/60°/65°/70°C) with anti-chattering dwell and safety."
    private static let manualCaption =
        "Holds your chosen cooling level. Condensation safety (< 36°C) remains active."
    private static let turboCaption =
        "Dispatches 100% maximum cooling power. Automatically decays to Auto after 15 minutes."

    init(width: CGFloat) {
        // The section title is a menu row of its own now, outside the panel.
        super.init(width: width, title: nil, labels: ["Auto", "Manual", "Turbo"],
                   captions: [Self.autoCaption, Self.manualCaption, Self.turboCaption])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setMode(_ mode: AppMode) {
        switch mode {
        case .auto:
            control.selectedSegment = 0
            setCaption(Self.autoCaption)
        case .manual:
            control.selectedSegment = 1
            setCaption(Self.manualCaption)
        case .turbo:
            control.selectedSegment = 2
            setCaption(Self.turboCaption)
        }
    }

    override func segmentChanged() {
        switch control.selectedSegment {
        case 0: onSelect?(.auto)
        case 1: onSelect?(.manual)
        case 2: onSelect?(.turbo)
        default: break
        }
    }
}

/// LED effect picker. Segment order follows `LedEffect.allCases`, so the
/// selected index is the effect's raw value.
final class LedEffectPickerView: SegmentedRowView {

    var onSelect: ((LedEffect) -> Void)?

    private static let captions: [String] = [
        "Light is turned off.",
        "Smooth multi-colour rainbow cycle.",
        "Pulsing breathing light pattern.",
        "Steady single-colour accent light.",
        "Auto: LED colour shifts from green (cool) to red (hot) tracking Mac temperature."
    ]

    init(width: CGFloat) {
        // Titled from outside the panel, like the cooling section.
        super.init(width: width, title: nil,
                   labels: LedEffect.allCases.map(\.title),
                   captions: Self.captions)
        control.selectedSegment = LedEffect.auto.rawValue
        setCaption(Self.captions[LedEffect.auto.rawValue])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSelected(_ effect: LedEffect) {
        control.selectedSegment = effect.rawValue
        setCaption(Self.captions[effect.rawValue])
    }

    override func segmentChanged() {
        guard let effect = LedEffect(rawValue: control.selectedSegment) else { return }
        setCaption(Self.captions[effect.rawValue])
        onSelect?(effect)
    }
}

/// Breath sub-style, shown only while the Breath effect is selected.
final class BreathStyleToggleView: SegmentedRowView {

    var onSelect: ((BreathStyle) -> Void)?

    init(width: CGFloat) {
        super.init(width: width, title: "BREATH STYLE",
                   labels: ["Colorful", "Monochrome"])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStyle(_ style: BreathStyle) {
        control.selectedSegment = (style == .colorful) ? 0 : 1
    }

    override func segmentChanged() {
        onSelect?(control.selectedSegment == 0 ? .colorful : .monochrome)
    }
}
