import AppKit

/// Labelled segmented control laid out as a modern macOS menu row.
///
/// Follows Apple HIG with `.automatic` capsule styling and equal segment distribution.
class SegmentedRowView: PanelRowView {

    static let rowHeight: CGFloat = 44

    let control: NSSegmentedControl
    private let captionLabel = NSTextField(wrappingLabelWithString: "")

    init(width: CGFloat, title: String?, labels: [String], captions: [String] = []) {
        control = NSSegmentedControl(labels: labels,
                                     trackingMode: .selectOne,
                                     target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))

        let hPad = UIStyle.panelContentX
        let content = width - hPad * 2

        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        control.selectedSegment = 0
        control.target = self
        control.action = #selector(segmentChanged)
        control.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        control.frame = NSRect(x: hPad, y: UIStyle.panelPad,
                               width: content, height: 28)
        control.autoresizingMask = .width
        addSubview(control)

        var top = UIStyle.panelPad + 28

        if !captions.isEmpty {
            captionLabel.font = UIStyle.captionFont
            captionLabel.textColor = .secondaryLabelColor
            captionLabel.preferredMaxLayoutWidth = content
            captionLabel.translatesAutoresizingMaskIntoConstraints = true
            let height = captions.map { text -> CGFloat in
                captionLabel.stringValue = text
                return ceil(captionLabel.fittingSize.height)
            }.max() ?? 0
            captionLabel.stringValue = captions[0]
            top += 4
            captionLabel.frame = NSRect(x: hPad, y: top, width: content, height: height)
            addSubview(captionLabel)
            top += height
        }

        if let title {
            top += 4
            frame.size.height = top + 14 + UIStyle.panelPad
            let header = UIStyle.sectionLabel(title)
            header.frame = NSRect(x: hPad, y: frame.height - UIStyle.panelPad - 14,
                                  width: content, height: 14)
            addSubview(header)
        } else {
            frame.size.height = top + UIStyle.panelPad
        }
    }

    func setCaption(_ text: String) {
        guard captionLabel.stringValue != text else { return }
        captionLabel.stringValue = text
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setEnabled(_ enabled: Bool) { control.isEnabled = enabled }

    @objc func segmentChanged() {}
}

/// Auto / Manual / Turbo — chooses which control loop owns the cooler.
final class ModeSwitchView: SegmentedRowView {

    var onSelect: ((AppMode) -> Void)?

    init(width: CGFloat) {
        super.init(width: width, title: nil, labels: ["Auto", "Manual", "Turbo"], captions: [])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setMode(_ mode: AppMode) {
        switch mode {
        case .auto:   control.selectedSegment = 0
        case .manual: control.selectedSegment = 1
        case .turbo:  control.selectedSegment = 2
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

/// LED effect picker.
final class LedEffectPickerView: SegmentedRowView {

    var onSelect: ((LedEffect) -> Void)?

    init(width: CGFloat) {
        super.init(width: width, title: nil,
                   labels: LedEffect.allCases.map(\.title),
                   captions: [])
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

/// Breath sub-style, shown only while the Breath/Pulse effect is selected.
final class BreathStyleToggleView: SegmentedRowView {

    var onSelect: ((BreathStyle) -> Void)?

    init(width: CGFloat) {
        super.init(width: width, title: "Pulse Style",
                   labels: ["Rainbow", "Monochrome"])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setStyle(_ style: BreathStyle) {
        control.selectedSegment = (style == .colorful) ? 0 : 1
    }

    override func segmentChanged() {
        onSelect?(control.selectedSegment == 0 ? .colorful : .monochrome)
    }
}
