import AppKit

/// The card at the top of the menu: the brand header and the Mac's own
/// temperature, drawn as one custom view.
///
/// Everything is drawn rather than composed from subviews — the layout is a
/// single top-to-bottom flow, which is far simpler to express as a cursor
/// walking down the card than as a tree of views. The cooler's panel used to
/// live here too; it is `CoolerPanelView` now, a row of its own, because it has
/// states in which it should disappear entirely.
final class StatusCardView: PanelRowView {

    /// Derived from the panel rather than hand-tuned, so restyling a font or
    /// changing the padding can't leave the last row clipped. The trailing gap
    /// is the one before the next panel — `CoolerPanelView` carries the card's
    /// bottom padding, and supplies it itself when that row is hidden.
    static var height: CGFloat {
        // Split into named parts: as one expression the type-checker crawls.
        let header: CGFloat = pad + logoSize + headerGap * 2
        return header + macPanelHeight + UIStyle.panelGap
    }

    /// Everything the card draws, passed in one value so the view holds no
    /// opinions about where any of it came from.
    struct ViewModel {
        var dieTempC: Double?
        var thermalState: ThermalState = .nominal
    }

    private var model = ViewModel()

    // ── Metrics ──────────────────────────────────────────────────────────────

    private static let pad = UIStyle.hPad
    // Panel metrics live in UIStyle, shared with every panelled section of the
    // menu, so this card and the control rows below it can never drift.
    private static let panelPad = UIStyle.panelPad
    private static let panelInset = UIStyle.panelInset
    private static let panelContentX = UIStyle.panelContentX
    private static let panelRadius = UIStyle.panelRadius
    private static let logoSize: CGFloat = 18
    /// Gap below the brand header, used twice: once by the header's own
    /// bottom margin and once before the first panel.
    private static let headerGap: CGFloat = 7
    private static let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let tempFont = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .light)
    private static let stateFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = .width
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(_ model: ViewModel) {
        self.model = model
        needsDisplay = true
    }

    // ── Drawing ──────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        // Lays down the menu backdrop; this row paints over it.
        super.draw(dirtyRect)
        var y = Self.pad
        drawBrandHeader(y: &y)
        y += Self.headerGap

        // Each group sits on its own surface. Hairline dividers put the Mac's
        // readings and the cooler's in one undifferentiated column, which read
        // as a single list of numbers rather than two sources; panels make the
        // boundary obvious at a glance. Settings keeps its own titled group
        // further down the menu.
        drawPanel(at: y, height: Self.macPanelHeight)
        var macY = y + Self.panelPad
        drawMacSection(y: &macY)
    }

    private func drawPanel(at y: CGFloat, height: CGFloat) {
        let inset = Self.panelInset
        let rect = NSRect(x: inset, y: y, width: bounds.width - inset * 2, height: height)
        UIStyle.panelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Self.panelRadius,
                     yRadius: Self.panelRadius).fill()
    }

    // Measured once from the font itself, so `height` above stays correct if it
    // is restyled — a hand-tuned card height silently clips its last row the
    // moment a font changes.
    private static let tempTextHeight = UIStyle.text("0", tempFont).size().height

    static let macPanelHeight = panelPad + 13 + tempTextHeight + panelPad

    /// The running app's version, shown beside the title. Read once — the
    /// bundle can't change under a running process.
    private static let versionText: String? =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "v\($0)" }

    /// Logo, title and version.
    private func drawBrandHeader(y: inout CGFloat) {
        let pad = Self.pad
        let logoSize = Self.logoSize
        RedMagicLogo.drawR(in: NSRect(x: pad, y: y + 1, width: logoSize, height: logoSize))

        let title = UIStyle.text("REDMAGIC COOLER", Self.headerFont)
        let titleX = pad + logoSize + 7
        title.draw(at: NSPoint(x: titleX, y: y + 2))

        if let versionText = Self.versionText {
            let version = UIStyle.text(versionText, UIStyle.captionFont, .tertiaryLabelColor)
            version.draw(at: NSPoint(x: titleX + title.size().width + 8, y: y + 5))
        }

        y += logoSize + Self.headerGap
    }

    /// Mac model, thermal pressure, and die temperature.
    private func drawMacSection(y: inout CGFloat) {
        let pad = Self.panelContentX
        UIStyle.text(SystemInfo.macModel, UIStyle.sectionFont, .tertiaryLabelColor)
            .draw(at: NSPoint(x: pad, y: y))

        let state = UIStyle.text(model.thermalState.rawValue, Self.stateFont, .secondaryLabelColor)
        state.draw(at: NSPoint(x: bounds.width - pad - state.size().width, y: y - 1))
        y += 13

        // The number is the reading. A bar under it restated the same value in
        // a second visual language, and the colour of the digits already says
        // "hot" faster than a track filling up does.
        let temp = UIStyle.text(SystemInfo.formatTemp(model.dieTempC),
                                Self.tempFont, UIStyle.textHeatColor(model.dieTempC))
        let tempHeight = temp.size().height
        temp.draw(in: NSRect(x: pad, y: y, width: 160, height: tempHeight))
        y += tempHeight
    }

}
