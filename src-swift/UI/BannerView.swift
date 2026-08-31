import AppKit

/// A small inline banner: an icon or spinner beside a message, on a tinted
/// rounded background.
///
/// Used for the three states the menu has to explain rather than merely show —
/// manual mode staying on, a switch in flight, and the LED being unavailable
/// while the cooler is off.
final class BannerView: NSView {

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

    private var style: Style = .warning
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    private let hPad: CGFloat = UIStyle.hPad
    private let inset: CGFloat = 8

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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSRect(x: hPad, y: 4, width: bounds.width - hPad * 2, height: bounds.height - 8)
        let path = NSBezierPath(roundedRect: bg, xRadius: 7, yRadius: 7)
        style.tint.withAlphaComponent(0.14).setFill()
        path.fill()
    }
}
