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

    private let hPad: CGFloat = UIStyle.panelContentX
    /// The highlight sits just inside the panel the row is drawn on.
    private let highlightInset: CGFloat = UIStyle.panelInset + 2

    init(width: CGFloat, title: String, symbol: String?) {
        // 22pt of content with UIStyle.panelPad above and below, so a row at
        // either end of its panel shows the same breathing room as every
        // other panelled section.
        let vPad = UIStyle.panelPad
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22 + vPad * 2))
        autoresizingMask = .width

        iconView.frame = NSRect(x: hPad, y: vPad + 3, width: 16, height: 16)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let symbol {
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        }
        addSubview(iconView)

        label.stringValue = title
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: hPad + 16 + 8, y: vPad + 2,
                             width: width - (hPad + 16 + 8) - hPad - 18, height: 17)
        addSubview(label)

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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted, isEnabled else { return }
        let rect = bounds.insetBy(dx: highlightInset, dy: UIStyle.panelPad - 2)
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

/// The small-caps label that titles a group of menu rows.
///
/// A plain disabled `NSMenuItem` did this until the rows started painting the
/// menu's backdrop themselves: a system-drawn item in the middle of them was a
/// translucent band across an otherwise covered menu. It draws nothing but its
/// own text — the backdrop comes from `PanelRowView`.
final class SectionHeaderRow: PanelRowView {

    private let title: String

    init(width: CGFloat, title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        autoresizingMask = .width
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        UIStyle.drawSectionHeader(title, at: NSPoint(x: UIStyle.hPad, y: 8))
    }
}

/// Blank space at the foot of the menu.
///
/// The last row used to sit flush against the window's bottom edge, which read
/// as the menu being clipped rather than finished. This is the margin — and,
/// being a row like any other, it paints the backdrop and rounds the window's
/// bottom corners on the real last row's behalf.
final class MenuFooterRow: PanelRowView {

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: UIStyle.panelPad))
        autoresizingMask = .width
        menuEdges = .bottom
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
