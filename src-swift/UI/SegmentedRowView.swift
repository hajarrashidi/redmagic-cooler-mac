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

/// Auto / Manual — chooses which control loop owns the cooler.
final class ModeSwitchView: SegmentedRowView {

    var onSelect: ((AppMode) -> Void)?

    /// One sentence per mode, and only the selected one is shown. Describing
    /// both at once meant half the caption was always about a mode the user had
    /// not chosen — and the Auto half named a threshold slider that Manual
    /// hides, so it pointed at something that wasn't on screen.
    private static let autoCaption =
        "Cooling follows the Mac's temperature: it starts at your engage "
        + "threshold and backs off as the Mac cools."
    private static let manualCaption =
        "Cooling holds the level you set until you change it, or until the "
        + "auto-off timer ends the session."

    init(width: CGFloat) {
        // The section title is a menu row of its own now, outside the panel.
        super.init(width: width, title: nil, labels: ["Auto", "Manual"],
                   captions: [Self.autoCaption, Self.manualCaption])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setMode(_ mode: AppMode) {
        control.selectedSegment = (mode == .auto) ? 0 : 1
        setCaption(mode == .auto ? Self.autoCaption : Self.manualCaption)
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
        // Titled from outside the panel, like the cooling section.
        super.init(width: width, title: nil,
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
