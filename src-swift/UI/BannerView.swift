import AppKit

/// A small inline banner: an icon or spinner beside a message, on a tinted
/// rounded background.
///
/// Used for the states the menu has to explain rather than merely show — manual
/// mode staying on, a switch in flight, the LED being unavailable while the
/// cooler is off, and a newer release being available.
///
/// Setting `onClick` turns the banner into a button; left nil it is purely
/// informational, which is what the first three uses want.
final class BannerView: PanelRowView {

    enum Style {
        case warning   // amber — manual stays on until turned off
        case info      // blue — switching in progress
        case neutral   // gray — cooler off, LED unavailable

        var tint: NSColor {
            switch self {
            case .warning: return .systemOrange
            case .info:    return .systemBlue
            case .neutral: return .secondaryLabelColor
            }
        }
    }

    /// Set to make the whole banner a button: a chevron appears on the trailing
    /// edge, the row lights up under the cursor, and clicking dismisses the menu.
    var onClick: (() -> Void)? {
        didSet { applyClickAffordance() }
    }

    private var style: Style = .warning
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let chevron = NSImageView()
    private var isHighlighted = false

    private let hPad: CGFloat = UIStyle.hPad
    private let inset: CGFloat = 8
    private let chevronWidth: CGFloat = 12

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 38))

        iconView.frame = NSRect(x: hPad + inset, y: 11, width: 16, height: 16)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.frame = NSRect(x: hPad + inset, y: 10, width: 16, height: 16)
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.frame = NSRect(x: hPad + inset + 16 + 8, y: 11, width: width - hPad * 2 - inset * 2 - 24, height: 16)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        chevron.frame = NSRect(x: width - hPad - inset - chevronWidth, y: 13,
                               width: chevronWidth, height: 12)
        chevron.imageScaling = .scaleProportionallyUpOrDown
        chevron.isHidden = true
        addSubview(chevron)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // ── Click affordance ─────────────────────────────────────────────────────

    /// Shows or hides the chevron and reserves room for it, so a long message
    /// truncates before it collides with the arrow.
    private func applyClickAffordance() {
        let clickable = (onClick != nil)
        chevron.isHidden = !clickable

        if clickable, chevron.image == nil {
            let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            chevron.image = NSImage(systemSymbolName: "chevron.right",
                                    accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
        }
        chevron.contentTintColor = style.tint

        let trailing = clickable ? chevronWidth + 6 : 0
        label.frame.size.width = bounds.width - hPad * 2 - inset * 2 - 24 - trailing
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setHoverTracking(enabled: onClick != nil)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let onClick else { return }
        // Read the menu before acting: the handler opens a browser, and leaving
        // the menu up behind a newly-focused window looks stuck.
        let menu = enclosingMenuItem?.menu
        onClick()
        menu?.cancelTracking()
    }

    func configure(style: Style, text: String, symbol: String, showSpinner: Bool) {
        self.style = style
        label.stringValue = text
        label.textColor = style.tint

        if showSpinner {
            iconView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            iconView.isHidden = false
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            iconView.contentTintColor = style.tint
        }
        // The tint travels with the style, so the chevron has to follow it.
        chevron.contentTintColor = style.tint
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Lays down the menu backdrop; this row paints over it.
        super.draw(dirtyRect)
        let bg = NSRect(x: hPad, y: 4, width: bounds.width - hPad * 2, height: bounds.height - 8)
        let path = NSBezierPath(roundedRect: bg, xRadius: 7, yRadius: 7)
        style.tint.withAlphaComponent(isHighlighted ? 0.26 : 0.14).setFill()
        path.fill()
    }
}
