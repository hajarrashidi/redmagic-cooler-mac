import AppKit

/// A labelled segmented control laid out as a menu row.
///
/// Three rows in this menu — cooling mode, LED effect, breath
/// style — were near-identical copies of the same 25 lines of framing code.
/// This is that layout, once. Subclasses supply their own typed API on top.
class SegmentedRowView: PanelRowView {

    /// 8 + header 13 + gap 5 + control 26 + 8 — panelPad at both edges. A row
    /// with a caption is taller by however many lines that caption wraps to.
    static let rowHeight: CGFloat = 60

    let control: NSSegmentedControl

    /// - Parameters:
    ///   - title: uppercase section header drawn above the control.
    ///   - labels: segment titles, in order.
    ///   - caption: optional sentence between the header and the control,
    ///     for a choice whose labels can't carry their own meaning.
    init(width: CGFloat, title: String, labels: [String], caption: String? = nil) {
        control = NSSegmentedControl(labels: labels,
                                     trackingMode: .selectOne,
                                     target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))

        let hPad = UIStyle.panelContentX
        let content = width - hPad * 2

        // Built bottom-up: this view is unflipped, and the caption's height is
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

        if let caption {
            let label = NSTextField(wrappingLabelWithString: caption)
            label.font = UIStyle.captionFont
            label.textColor = .tertiaryLabelColor
            label.preferredMaxLayoutWidth = content
            let height = ceil(label.fittingSize.height)
            // `wrappingLabelWithString` hands back an Auto Layout field; every
            // row here is placed by frame, and a constraint-driven label with
            // no constraints collapses to nothing.
            label.translatesAutoresizingMaskIntoConstraints = true
            top += 6
            label.frame = NSRect(x: hPad, y: top, width: content, height: height)
            addSubview(label)
            top += height + 3
            frame.size.height = top + 13 + UIStyle.panelPad
        }

        let header = UIStyle.sectionLabel(title)
        header.frame = NSRect(x: hPad, y: frame.height - UIStyle.panelPad - 13,
                              width: content, height: 13)
        addSubview(header)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Greys the control out while a change is in flight.
    func setEnabled(_ enabled: Bool) { control.isEnabled = enabled }

    /// Overridden by subclasses to publish their typed selection.
    @objc func segmentChanged() {}
}

/// Auto / Manual — chooses which control loop owns the cooler.
final class ModeSwitchView: SegmentedRowView {

    var onSelect: ((AppMode) -> Void)?

    init(width: CGFloat) {
        // Two words that both sound like "it cools". Which one is in charge of
        // the fan, and when, is the thing the menu was never saying.
        super.init(width: width, title: "COOLING", labels: ["Auto", "Manual"],
                   // No "the slider below": that slider is hidden in Manual,
                   // and a caption that points at something absent is worse
                   // than one that names it.
                   caption: "Auto turns cooling on by itself once the Mac "
                          + "passes your engage threshold, and backs off as it "
                          + "cools. Manual holds one level until you change it.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setMode(_ mode: AppMode) {
        control.selectedSegment = (mode == .auto) ? 0 : 1
    }

    override func segmentChanged() {
        onSelect?(control.selectedSegment == 0 ? .auto : .manual)
    }
}

/// LED effect picker. Segment order follows `LedEffect.allCases`, so the
/// selected index is the effect's raw value.
final class LedEffectPickerView: SegmentedRowView {

    var onSelect: ((LedEffect) -> Void)?

    init(width: CGFloat) {
        super.init(width: width, title: "LED EFFECT",
                   labels: LedEffect.allCases.map(\.title))
        control.selectedSegment = LedEffect.auto.rawValue
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSelected(_ effect: LedEffect) {
        control.selectedSegment = effect.rawValue
    }

    override func segmentChanged() {
        guard let effect = LedEffect(rawValue: control.selectedSegment) else { return }
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
