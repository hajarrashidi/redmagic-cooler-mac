import AppKit

/// A labelled segmented control laid out as a menu row.
///
/// Four rows in this menu — cooling mode, auto profile, LED effect, breath
/// style — were near-identical copies of the same 25 lines of framing code.
/// This is that layout, once. Subclasses supply their own typed API on top.
class SegmentedRowView: NSView {

    static let rowHeight: CGFloat = 50

    let control: NSSegmentedControl

    /// - Parameters:
    ///   - title: uppercase section header drawn above the control.
    ///   - labels: segment titles, in order.
    init(width: CGFloat, title: String, labels: [String]) {
        control = NSSegmentedControl(labels: labels,
                                     trackingMode: .selectOne,
                                     target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))

        let hPad = UIStyle.hPad
        let header = NSTextField(labelWithString: title)
        header.font = UIStyle.sectionFont
        header.textColor = .tertiaryLabelColor
        header.frame = NSRect(x: hPad, y: 34, width: width - hPad * 2, height: 13)
        addSubview(header)

        control.segmentStyle = .rounded
        control.selectedSegment = 0
        control.target = self
        control.action = #selector(segmentChanged)
        control.frame = NSRect(x: hPad, y: 6, width: width - hPad * 2, height: 26)
        control.autoresizingMask = .width
        addSubview(control)
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
        super.init(width: width, title: "COOLING", labels: ["Auto", "Manual"])
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
