import AppKit

/// Unified Hardware Deck (Upper Half): Brand header, Mac thermal state and die temperature.
///
/// Shares a continuous rounded panel with `CoolerPanelView` directly below it,
/// forming a unified hardware status card with zero vertical clutter.
final class StatusCardView: PanelRowView {

    static let cardHeight: CGFloat = 68
    static var height: CGFloat { cardHeight }

    struct ViewModel {
        var dieTempC: Double?
        var thermalState: ThermalState = .nominal
    }

    private var model = ViewModel()

    // ── Metrics ──────────────────────────────────────────────────────────────
    private static let pad = UIStyle.panelContentX
    private static let logoSize: CGFloat = 16
    private static let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let tempFont = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .medium)
    private static let modelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let stateFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let subFont = NSFont.systemFont(ofSize: 10, weight: .regular)

    private static let versionText: String? =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "v\($0)" }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.cardHeight))
        autoresizingMask = .width
        panelSegment = .top
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func update(_ model: ViewModel) {
        self.model = model
        needsDisplay = true
    }

    // ── Drawing ──────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = Self.pad

        // 1. Top Header Row (y = 10)
        let topY: CGFloat = 10
        RedMagicLogo.drawR(in: NSRect(x: pad, y: topY + 1, width: Self.logoSize, height: Self.logoSize))

        let title = UIStyle.text("Smart Cooler Control", Self.headerFont, .labelColor)
        let titleX = pad + Self.logoSize + 6
        title.draw(at: NSPoint(x: titleX, y: topY))

        if let versionText = Self.versionText {
            let version = UIStyle.text(versionText, Self.subFont, .tertiaryLabelColor)
            version.draw(at: NSPoint(x: titleX + title.size().width + 6, y: topY + 2))
        }

        // Right side: Mac Model + Thermal State Dot
        let stateColor = thermalColor(model.thermalState)
        let stateStr = "● \(model.thermalState.rawValue.capitalized)"
        let stateText = UIStyle.text(stateStr, Self.stateFont, stateColor)
        let modelText = UIStyle.text(SystemInfo.macModel, Self.modelFont, .secondaryLabelColor)

        let rightX = bounds.width - pad - stateText.size().width
        stateText.draw(at: NSPoint(x: rightX, y: topY + 1))
        let modelX = rightX - modelText.size().width - 8
        modelText.draw(at: NSPoint(x: modelX, y: topY + 1))

        // 2. Hero Temperature Row (y = 30)
        let tempY: CGFloat = 30
        let tempStr = SystemInfo.formatTemp(model.dieTempC)
        let tempColor = UIStyle.textHeatColor(model.dieTempC)
        let tempText = UIStyle.text(tempStr, Self.tempFont, tempColor)
        tempText.draw(at: NSPoint(x: pad, y: tempY))

        let tempWidth = tempText.size().width
        let labelY = tempY + 10
        let tempLabel = UIStyle.text("Die / CPU", Self.subFont, .tertiaryLabelColor)
        tempLabel.draw(at: NSPoint(x: pad + tempWidth + 8, y: labelY))
    }

    private func thermalColor(_ state: ThermalState) -> NSColor {
        switch state {
        case .nominal:  return .systemGreen
        case .fair:     return .systemYellow
        case .serious:  return .systemOrange
        case .critical: return .systemRed
        }
    }
}
