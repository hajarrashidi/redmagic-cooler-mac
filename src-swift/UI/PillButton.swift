import AppKit

/// A compact rounded button sized to its title.
///
/// The stock bezelled `NSButton` paints an opaque capsule that fights the soft
/// translucent panels every row in this menu is drawn on, and it reacts to the
/// cursor only once it has already been pressed. Inside a menu — where nothing
/// else is a control — that left Connect and Scan reading as labels nobody
/// thought to click. This draws the same rounded shape as the panels and lights
/// up under the pointer.
final class PillButton: NSView {

    var onClick: (() -> Void)?

    var title: String {
        didSet {
            guard title != oldValue else { return }
            label.stringValue = title
            needsDisplay = true
        }
    }

    /// Greyed out and unclickable — for a button whose action is already
    /// running, or that Bluetooth being off would make pointless.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            // Otherwise a button disabled under the cursor keeps its hover fill
            // until the pointer happens to leave it.
            if !isEnabled { isHovered = false }
            applyTint()
        }
    }

    static let height: CGFloat = 24
    private static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// Room either side of the title, generous enough that a one-word button
    /// still reads as a target rather than as boxed text.
    private static let hPad: CGFloat = 12
    private static let labelHeight: CGFloat = 15

    /// Width this button wants for its current title. Callers place the button
    /// themselves — a trailing-aligned one has to move when its title grows —
    /// so the size is offered rather than applied.
    var fittingWidth: CGFloat {
        ceil(UIStyle.text(title, Self.font).size().width) + Self.hPad * 2
    }

    /// Set by whichever view owns the mouse for this row.
    ///
    /// A tracking area of its own would be the obvious way, and it is what this
    /// used to do — but a button nested inside a menu item's view never sees
    /// the cursor. `NSMenu` tracks the mouse itself and hands events to the
    /// item's view; nothing below that gets `mouseEntered`. So the item view
    /// routes hover down, and this just paints what it is told.
    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        label.font = Self.font
        label.alignment = .center
        label.stringValue = title
        addSubview(label)
        applyTint()
        setFrameSize(NSSize(width: fittingWidth, height: Self.height))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Keeps the label centred however the caller sizes the button.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        label.frame = NSRect(x: 0, y: (newSize.height - Self.labelHeight) / 2,
                             width: newSize.width, height: Self.labelHeight)
    }

    // ── Appearance ───────────────────────────────────────────────────────────

    private func applyTint() {
        label.textColor = isEnabled ? .controlAccentColor : .tertiaryLabelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor = isEnabled
            ? NSColor.controlAccentColor.withAlphaComponent(isHovered ? 0.38 : 0.15)
            : NSColor.labelColor.withAlphaComponent(0.05)
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    /// Called by the row that owns the mouse, once it has decided the click
    /// landed here.
    func performClick() {
        guard isEnabled else { return }
        onClick?()
    }

    /// Consumes the click when AppKit does dispatch it this deep. Whether it
    /// does is up to the menu; not calling `super` means the owning row's own
    /// `mouseUp` runs instead of as well, never both.
    override func mouseUp(with event: NSEvent) {
        performClick()
    }
}

/// A caption-sized text link that underlines under the cursor.
///
/// A borderless `NSButton` tinted `.linkColor` looks the part but behaves like
/// static text: no hover, no hint that it goes anywhere. The porting-guide link
/// is the one thing in the picker an owner of an unrecognised cooler needs to
/// find, so it says so when the pointer reaches it.
final class LinkButton: NSView {

    var onClick: (() -> Void)?

    var title: String {
        didSet {
            guard title != oldValue else { return }
            applyTitle()
        }
    }

    /// Set by the row that owns the mouse — see `PillButton.isHovered`.
    var isHovered = false {
        didSet { if isHovered != oldValue { applyTitle() } }
    }

    static let height: CGFloat = 16

    /// Width of the text itself. Callers size the link to it so the hover
    /// underline answers the cursor over the words, not over a full-width
    /// strip of empty space beside them.
    var fittingWidth: CGFloat {
        // Measured with the underline already applied: it is the wider of the
        // two states, and a link that reflows on hover reads as a glitch.
        ceil(UIStyle.text(title, UIStyle.captionFont).size().width) + 2
    }

    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.height))
        addSubview(label)
        applyTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        label.frame = NSRect(origin: .zero, size: newSize)
    }

    private func applyTitle() {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIStyle.captionFont,
            .foregroundColor: UIStyle.linkInk,
        ]
        if isHovered {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        label.attributedStringValue = NSAttributedString(string: title, attributes: attributes)
    }

    /// Called by the row that owns the mouse, once it has decided the click
    /// landed here.
    func performClick() {
        onClick?()
    }

    /// See `PillButton.mouseUp`.
    override func mouseUp(with event: NSEvent) {
        performClick()
    }
}
