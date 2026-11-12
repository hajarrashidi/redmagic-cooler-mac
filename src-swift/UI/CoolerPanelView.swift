import AppKit

/// Unified Hardware Deck (Lower Half): Cooler model, live telemetry, and animated fan.
///
/// Shares the continuous rounded panel with `StatusCardView` directly above it.
final class CoolerPanelView: PanelRowView {

    enum Note: Equatable {
        case switching
        case manualStaysOn
        case powerSwitchOff
        case autoWaiting(shutoffC: Int)
        case manualTimedOut
        case safetyIntercepted(cutoffC: Double, rearmC: Double)
        case turboMax

        var text: String {
            switch self {
            case .switching:             return "Comutando modo… aguarde"
            case .manualStaysOn:         return "Modo Manual contínuo"
            case .powerSwitchOff:        return "Chave de energia desligada ou ocioso"
            case .autoWaiting(let shut): return "Standby: Mac abaixo de \(shut)°C"
            case .manualTimedOut:        return "Auto-off encerrou o resfriamento manual"
            case .safetyIntercepted(let cutoff, let rearm):
                return "🛡️ Corte de segurança: < \(Int(round(cutoff)))°C (retoma ≥ \(Int(round(rearm)))°C)"
            case .turboMax:
                return "Turbo Boost 100% (Proteção < 36°C ativa)"
            }
        }

        var symbol: String {
            switch self {
            case .switching:         return "arrow.triangle.2.circlepath"
            case .manualStaysOn,
                 .manualTimedOut:    return "exclamationmark.triangle"
            case .powerSwitchOff:    return "power.circle.fill"
            case .autoWaiting:       return "thermometer.medium"
            case .safetyIntercepted: return "shield.fill"
            case .turboMax:          return "bolt.fill"
            }
        }

        var tint: NSColor {
            switch self {
            case .switching:         return .systemBlue
            case .powerSwitchOff:    return .systemOrange
            case .manualStaysOn,
                 .manualTimedOut:    return .labelColor
            case .autoWaiting:       return .secondaryLabelColor
            case .safetyIntercepted: return .systemTeal
            case .turboMax:          return .systemRed
            }
        }
    }

    struct ViewModel {
        var isConnected = false
        var phase: ConnectionPhase = .idle
        var deviceModelName: String?
        var telemetry: CoolerTelemetry?
        var mode: CoolingMode = .off
        var fanPercent: UInt8 = 0
        var statusDetail: String? = nil
        var deviceLooksPoweredOff = false
        var note: Note?
        var actionsEnabled = true
    }

    var onConnect: (() -> Void)?

    private var model = ViewModel()
    private var noteSymbol: NSImage?
    private let connectButton = PillButton(title: "Connect")

    // ── Metrics ──────────────────────────────────────────────────────────────
    static let panelHeight: CGFloat = 66
    static let height: CGFloat = panelHeight

    private static let pad = UIStyle.panelContentX
    private static let fanSize: CGFloat = 24
    private static let titleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static let statusFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let telemetryFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
    private static let noteFont = NSFont.systemFont(ofSize: 9.5, weight: .medium)

    // ── Fan animation ────────────────────────────────────────────────────────
    private var fanAngle: CGFloat = 0
    private var animationTimer: Timer?
    private static let spinRatePerZone: CGFloat = 0.055
    private static let frameInterval: TimeInterval = 1.0 / 30.0

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        autoresizingMask = .width
        panelSegment = .bottom

        connectButton.onClick = { [weak self] in self?.onConnect?() }
        connectButton.autoresizingMask = .minXMargin
        addSubview(connectButton)
        layOutConnectButton()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    // ── Mouse & Connect Button ───────────────────────────────────────────────

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        connectButton.isHovered = !connectButton.isHidden
            && connectButton.frame.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { connectButton.isHovered = false }

    override func mouseUp(with event: NSEvent) {
        guard !connectButton.isHidden,
              connectButton.frame.contains(convert(event.locationInWindow, from: nil))
        else { return }
        connectButton.performClick()
    }

    func update(_ model: ViewModel) {
        if model.note != self.model.note {
            noteSymbol = model.note.map {
                Self.tinted($0.symbol, size: 9, color: $0.tint)
            } ?? nil
        }
        self.model = model
        syncConnectButton()
        needsDisplay = true
    }

    private func syncConnectButton() {
        connectButton.isHidden = model.isConnected
        guard !model.isConnected else { return }
        connectButton.title = model.phase.connectButtonTitle
        connectButton.isEnabled = model.phase.allowsConnectAction && model.actionsEnabled
        layOutConnectButton()
    }

    private func layOutConnectButton() {
        let width = connectButton.fittingWidth
        connectButton.frame = NSRect(
            x: bounds.width - Self.pad - width,
            y: (Self.panelHeight - PillButton.height) / 2,
            width: width, height: PillButton.height)
    }

    // ── Animation ────────────────────────────────────────────────────────────

    func startAnimating() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            guard let self, self.model.isConnected else { return }
            guard !self.model.deviceLooksPoweredOff else { return }
            let zone = self.model.mode.zone.rawValue
            guard zone > 0 else { return }
            self.fanAngle += CGFloat(zone) * Self.spinRatePerZone
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private var runningZone: CoolingMode.Zone {
        guard model.isConnected, !model.deviceLooksPoweredOff else { return .off }
        return model.mode.zone
    }

    // ── Drawing ──────────────────────────────────────────────────────────────

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = Self.pad
        let contentWidth = bounds.width - pad * 2

        // Hairline boundary with upper deck
        let divRect = NSRect(x: pad, y: 0, width: contentWidth, height: 1)
        NSColor.separatorColor.withAlphaComponent(0.12).setFill()
        divRect.fill()

        // 1. Device Title (y = 8)
        let nameY: CGFloat = 8
        let deviceTitle = cleanDeviceName(model.deviceModelName)
        let title = UIStyle.text(deviceTitle, Self.titleFont, .labelColor)
        title.draw(at: NSPoint(x: pad, y: nameY))

        // Fan or Connect Button
        if model.isConnected {
            let fanX = bounds.width - pad - Self.fanSize
            let fanRect = NSRect(x: fanX, y: (Self.panelHeight - Self.fanSize) / 2,
                                 width: Self.fanSize, height: Self.fanSize)
            FanGlyph.draw(in: fanRect, angleRadians: fanAngle,
                          color: model.mode.isOn ? .controlAccentColor : .tertiaryLabelColor,
                          zone: runningZone)
        }

        // 2. Connection Line (y = 26)
        let connY: CGFloat = 26
        let connText = model.isConnected ? "Connected over Bluetooth" : model.phase.statusText
        let connColor = model.isConnected ? NSColor.secondaryLabelColor : phaseColor()
        let maxConnWidth = model.isConnected ? (bounds.width - pad * 2 - Self.fanSize - 12) : (connectButton.frame.minX - pad - 8)
        let connAttr = UIStyle.text(connText, Self.statusFont, connColor)
        connAttr.draw(in: NSRect(x: pad, y: connY, width: max(maxConnWidth, 1), height: 15))

        // 3. Operational State or Note Line (y = 44)
        let bottomY: CGFloat = 44
        if let note = model.note {
            var x = pad
            if let noteSymbol {
                let size = noteSymbol.size
                noteSymbol.draw(in: NSRect(x: x, y: bottomY + (13 - size.height) / 2,
                                           width: size.width, height: size.height),
                                from: .zero, operation: .sourceOver, fraction: 1,
                                respectFlipped: true, hints: nil)
                x += size.width + 5
            }
            UIStyle.text(note.text, Self.noteFont, note.tint)
                .draw(in: NSRect(x: x, y: bottomY, width: max(bounds.width - x - pad - (model.isConnected ? Self.fanSize + 8 : 0), 1), height: 14))
        } else if model.isConnected {
            let opText: String
            let opColor: NSColor
            if let detail = model.statusDetail {
                opText = detail
                opColor = model.mode.isOn ? .systemGreen : .secondaryLabelColor
            } else if model.mode.isOn {
                opText = "Ativo (\(model.fanPercent)%)"
                opColor = .systemGreen
            } else {
                opText = "Standby"
                opColor = .tertiaryLabelColor
            }
            let dot = model.mode.isOn ? "● " : "○ "
            let maxOpWidth = bounds.width - pad * 2 - Self.fanSize - 12
            UIStyle.text("\(dot)\(opText)", Self.statusFont, opColor)
                .draw(in: NSRect(x: pad, y: bottomY, width: max(maxOpWidth, 1), height: 14))
        }
    }

    private func cleanDeviceName(_ raw: String?) -> String {
        guard let raw else { return "Cooler Inteligente" }
        // Format shouting device names to concise title case while preserving model & wattage
        if raw.contains("REDMAGIC") || raw.contains("RM ") {
            if raw.contains("6 Pro+") || raw.contains("6pro+") { return "REDMAGIC 6 Pro+ (40W)" }
            if raw.contains("5") { return "REDMAGIC 5 Pro (36W)" }
            if raw.contains("6") { return "REDMAGIC 6 Pro (36W)" }
            if raw.contains("8") { return "REDMAGIC Cryo 8 Pro (36W)" }
            if raw.contains("4") { return "REDMAGIC 4 Pro (27W)" }
            return "REDMAGIC Cooler"
        }
        if raw.contains("Black Shark") || raw.contains("BS ") {
            if raw.contains("5") { return "Black Shark 5 Pro (35W)" }
            if raw.contains("4") { return "Black Shark 4 Pro (27W)" }
            return "Black Shark MagCooler"
        }
        if raw.contains("Flydigi") {
            if raw.contains("B8X") { return "Flydigi B8X (30W)" }
            if raw.contains("B7X") { return "Flydigi B7X (27W)" }
            return "Flydigi Cooler"
        }
        return raw
    }

    private static func tinted(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        return NSImage(size: base.size, flipped: false) { rect in
            color.set()
            base.draw(in: rect)
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private func phaseColor() -> NSColor {
        switch model.phase {
        case .bluetoothOff:          return .systemRed
        case .bluetoothUnauthorized: return .systemOrange
        case .idle:                  return .tertiaryLabelColor
        default:                     return .secondaryLabelColor
        }
    }
}
