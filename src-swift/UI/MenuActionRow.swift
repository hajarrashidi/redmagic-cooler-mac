import AppKit

/// A menu row that acts like an ordinary item but can leave the menu open.
///
/// AppKit dismisses the menu on any standard `NSMenuItem` click and offers no
/// flag to opt out. That is wrong for an action whose whole result appears
/// *inside* the menu: "Change Device" swaps the rows below it for the inline
/// picker, which the user never sees if the menu closes in the same gesture.
///
/// Custom views don't auto-dismiss, so this is hand-drawn to pass for a system
/// item — menu font, 16pt symbol, and the accent-filled rounded highlight macOS
/// has used since Big Sur. The settings rows also use it, for the panel it can
/// sit on; they opt back into ordinary dismissal with `dismissesMenu`.
final class MenuActionRow: PanelRowView {

    var onClick: (() -> Void)?

    /// Closes the menu after the click, like an ordinary item. Off by default —
    /// the row was invented for actions whose result shows *inside* the menu —
    /// but the settings rows use it to keep behaving the way their former plain
    /// items did.
    var dismissesMenu = false

    /// Shows a trailing checkmark, for a row that is a toggle ("Start at
    /// Login") rather than a one-shot action.
    var isChecked = false {
        didSet { checkView.isHidden = !isChecked }
    }

    /// Greyed out and unclickable, for a row that is information rather than an
    /// action — a cooler we can see but have no profile for.
    var isEnabled = true {
        didSet {
            applyTint()
            updateTrackingAreas()
        }
    }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let checkView = NSImageView()
    private var isHighlighted = false

    private let hPad: CGFloat = UIStyle.panelContentX
    /// The highlight sits just inside the panel the row is drawn on.
    private let highlightInset: CGFloat = UIStyle.panelInset + 2

    init(width: CGFloat, title: String, symbol: String?) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = .width

        iconView.frame = NSRect(x: hPad, y: 3, width: 16, height: 16)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let symbol {
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        }
        addSubview(iconView)

        label.stringValue = title
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: hPad + 16 + 8, y: 2,
                             width: width - (hPad + 16 + 8) - hPad - 18, height: 17)
        addSubview(label)

        checkView.frame = NSRect(x: width - hPad - 14, y: 4, width: 14, height: 14)
        checkView.imageScaling = .scaleProportionallyUpOrDown
        checkView.image = NSImage(systemSymbolName: "checkmark",
                                  accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        checkView.isHidden = true
        addSubview(checkView)

        applyTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // ── Appearance ───────────────────────────────────────────────────────────

    private func applyTint() {
        let color: NSColor
        if !isEnabled {
            color = .tertiaryLabelColor
        } else if isHighlighted {
            color = .selectedMenuItemTextColor
        } else {
            color = .labelColor
        }
        label.textColor = color
        iconView.contentTintColor = color
        checkView.contentTintColor = color
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted, isEnabled else { return }
        let rect = bounds.insetBy(dx: highlightInset, dy: 0)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
    }

    // ── Tracking ─────────────────────────────────────────────────────────────

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setHoverTracking(enabled: isEnabled)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        applyTint()
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        applyTint()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        // Read the menu before acting — the handler may mutate the rows.
        let menu = dismissesMenu ? enclosingMenuItem?.menu : nil
        onClick?()
        menu?.cancelTracking()
    }
}
