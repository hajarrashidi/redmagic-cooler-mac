import AppKit

/// The Manual auto-off picker: 1h / 2h / 3h / ∞, with the time left beside it.
///
/// It rides along with the power slider, shown only in Manual, because that is
/// the only mode with anything to run out. The countdown sits on the header
/// line rather than under the control: it changes every minute, and a number
/// that moves is better placed where the eye already goes for the section's
/// name than dropped below the thing it describes.
final class ManualTimerView: SegmentedRowView {

    /// Emitted for any selection, `unlimited` included. Confirming that choice
    /// is the app's business, not this view's — the view only reports what was
    /// clicked, and `setTimeout` puts the selection back if the answer is no.
    var onSelect: ((ManualTimer.Timeout) -> Void)?

    private let remainingLabel = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(width: width, title: "AUTO-OFF",
                   labels: ManualTimer.Timeout.allCases.map(\.label))

        remainingLabel.font = UIStyle.captionFont
        remainingLabel.textColor = .secondaryLabelColor
        remainingLabel.alignment = .right
        // Sits on the header's line, at the far end of it.
        let hPad = UIStyle.panelContentX
        // Same box as the header it shares a line with, so the two baselines
        // agree despite the different font sizes.
        remainingLabel.frame = NSRect(x: width / 2, y: frame.height - UIStyle.panelPad - 13,
                                      width: width / 2 - hPad, height: 13)
        remainingLabel.autoresizingMask = .minXMargin
        addSubview(remainingLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setTimeout(_ timeout: ManualTimer.Timeout) {
        control.selectedSegment =
            ManualTimer.Timeout.allCases.firstIndex(of: timeout) ?? 0
    }

    /// `nil` clears the line — either nothing is running or the limit is off.
    func setRemaining(_ text: String?) {
        remainingLabel.stringValue = text.map { "\($0) left" } ?? ""
    }

    override func segmentChanged() {
        let choices = ManualTimer.Timeout.allCases
        guard choices.indices.contains(control.selectedSegment) else { return }
        let choice = choices[control.selectedSegment]

        // Unlimited is confirmed in an alert, and a modal cannot open under a
        // tracking menu — the menu has to go first. Everything else leaves the
        // menu up, because the countdown it just changed is displayed in it.
        if choice == .unlimited {
            enclosingMenuItem?.menu?.cancelTracking()
        }
        onSelect?(choice)
    }
}
