import AppKit

/// A menu row that acts like an ordinary item but leaves the menu open.
///
/// AppKit dismisses the menu on any standard `NSMenuItem` click and offers no
/// flag to opt out. That is wrong for an action whose whole result appears
/// *inside* the menu: "Change Device" swaps the rows below it for the inline
/// picker, which the user never sees if the menu closes in the same gesture.
///
/// Custom views don't auto-dismiss, so this is hand-drawn to pass for a system
/// item — menu font, 16pt symbol, and the accent-filled rounded highlight macOS
/// has used since Big Sur. Rows that *should* close the menu keep using plain
/// items; `DevicePickerView` dismisses explicitly via `cancelTracking()`.
final class MenuActionRow: NSView {

    var onClick: (() -> Void)?

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
    private var isHighlighted = false

    private let hPad: CGFloat = UIStyle.hPad
    /// macOS insets the highlight from the menu's edges rather than filling it.
    private let highlightInset: CGFloat = 5

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
                             width: width - (hPad + 16 + 8) - hPad, height: 17)
        addSubview(label)

        applyTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setTitle(_ title: String) {
        label.stringValue = title
    }

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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted, isEnabled else { return }
        let rect = bounds.insetBy(dx: highlightInset, dy: 0)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
    }

    // ── Tracking ─────────────────────────────────────────────────────────────

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard isEnabled else { return }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp],
                                       owner: self))
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
        // Deliberately no cancelTracking(): the point of this row is that the
        // menu stays open so the user can see what the click changed.
        onClick?()
    }
}
