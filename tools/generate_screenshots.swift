import AppKit
import Foundation

/// Authentic macOS menu bar header + popup menu container for documentation screenshots.
final class MenuPopupContainerView: NSView {
    override var isFlipped: Bool { true }

    init(width: CGFloat, rows: [NSView]) {
        var totalHeight: CGFloat = 0
        for r in rows {
            totalHeight += r.frame.height
        }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))

        var y: CGFloat = 0
        for r in rows {
            r.frame.origin = CGPoint(x: 0, y: y)
            addSubview(r)
            y += r.frame.height
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Outer rounded border matching macOS Sonoma/Sequoia dark menu popup
        let borderRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let borderPath = NSBezierPath(roundedRect: borderRect, xRadius: UIStyle.menuCornerRadius, yRadius: UIStyle.menuCornerRadius)
        NSColor(white: 1.0, alpha: 0.22).setStroke()
        borderPath.lineWidth = 1.0
        borderPath.stroke()
    }
}

/// Renders the macOS top menu bar pill `[S 42°]` above the popup menu on a clean dark studio canvas.
final class ShowcaseCanvasView: NSView {
    override var isFlipped: Bool { true }

    private let menuBarTemp: String
    private let menuView: NSView
    private let hPad: CGFloat = 24
    private let topBarHeight: CGFloat = 34
    private let menuTopY: CGFloat = 42
    private let bottomPad: CGFloat = 24

    init(menuBarTemp: String, menuView: NSView) {
        self.menuBarTemp = menuBarTemp
        self.menuView = menuView
        let w = menuView.bounds.width + hPad * 2
        let h = menuTopY + menuView.bounds.height + bottomPad
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))

        menuView.frame.origin = CGPoint(x: hPad, y: menuTopY)
        addSubview(menuView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // 1. Rich dark macOS desktop backdrop
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0),
                                  ending: NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.06, alpha: 1.0))
        gradient?.draw(in: bgPath, angle: 90)

        // 2. Top macOS menu bar strip
        let barRect = NSRect(x: 0, y: 0, width: bounds.width, height: topBarHeight)
        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 0.95).setFill()
        NSBezierPath(rect: barRect).fill()

        NSColor(white: 1.0, alpha: 0.08).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: topBarHeight - 1, width: bounds.width, height: 1)).fill()

        // 3. Highlighted status item pill `[S 42°]`
        let pillRect = NSRect(x: hPad, y: 5, width: 66, height: 24)
        NSColor(white: 1.0, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()

        let logoImg = RedMagicLogo.image(size: 14, color: .white)
        logoImg.draw(in: NSRect(x: pillRect.minX + 9, y: pillRect.minY + 5, width: 14, height: 14))

        let pillAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let tempStr = NSAttributedString(string: menuBarTemp, attributes: pillAttrs)
        let tSize = tempStr.size()
        tempStr.draw(at: NSPoint(x: pillRect.minX + 27, y: pillRect.minY + (pillRect.height - tSize.height) / 2))

        // 4. Drop shadow behind the popup menu
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0.0, alpha: 0.65)
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.shadowBlurRadius = 20
        shadow.set()

        let menuShadowPath = NSBezierPath(roundedRect: menuView.frame,
                                          xRadius: UIStyle.menuCornerRadius,
                                          yRadius: UIStyle.menuCornerRadius)
        NSColor(white: 0.14, alpha: 1.0).setFill()
        menuShadowPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Custom showcase row displaying discovered multi-brand >=30W coolers in the Device Picker.
final class PopulatedDevicePickerRow: PanelRowView {
    override var isFlipped: Bool { true }

    private struct MockDevice {
        let name: String
        let power: String
        let isHovered: Bool
    }

    private let items: [MockDevice] = [
        MockDevice(name: "REDMAGIC Cooler 5 Pro (36W)", power: "Connected", isHovered: true),
        MockDevice(name: "REDMAGIC VC Cooler 6 Pro+ (40W)", power: "Excellent", isHovered: false),
        MockDevice(name: "Black Shark MagCooler 5 Pro (35W)", power: "Good", isHovered: false),
        MockDevice(name: "Flydigi B8X Overclock (30W)", power: "Good", isHovered: false),
        MockDevice(name: "OnePlus 45W Liquid Cooler (45W)", power: "Good", isHovered: false),
        MockDevice(name: "MEMO CX08 Magnetic Cooler (36W)", power: "Fair", isHovered: false),
    ]

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 268))
        panelSegment = .only

        let pad = UIStyle.panelContentX
        let content = width - pad * 2

        let scanBtn = PillButton(title: "Scan Again")
        scanBtn.frame = NSRect(x: pad, y: 204, width: content, height: PillButton.height)
        addSubview(scanBtn)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pad = UIStyle.panelContentX
        let content = bounds.width - pad * 2
        var y: CGFloat = UIStyle.panelPad

        // Status subtitle
        let statusAttrs: [NSAttributedString.Key: Any] = [
            .font: UIStyle.captionFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSAttributedString(string: "Select a supported ≥ 30W cooler to connect:", attributes: statusAttrs)
            .draw(at: NSPoint(x: pad, y: y))
        y += 22

        // Group header
        let groupAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 0.6
        ]
        NSAttributedString(string: "SUPPORTED COOLERS NEARBY", attributes: groupAttrs)
            .draw(at: NSPoint(x: pad + 4, y: y))
        y += 18

        // Device rows
        for item in items {
            let rowRect = NSRect(x: pad, y: y, width: content, height: 24)
            if item.isHovered {
                NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 6, yRadius: 6).fill()
            }

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: item.isHovered ? .medium : .regular),
                .foregroundColor: NSColor.labelColor
            ]
            NSAttributedString(string: item.name, attributes: nameAttrs)
                .draw(at: NSPoint(x: rowRect.minX + 8, y: rowRect.minY + 4))

            let sigAttrs: [NSAttributedString.Key: Any] = [
                .font: UIStyle.captionFont,
                .foregroundColor: item.isHovered ? NSColor.white.withAlphaComponent(0.95) : NSColor.secondaryLabelColor
            ]
            let sigStr = NSAttributedString(string: item.power, attributes: sigAttrs)
            let sigSize = sigStr.size()
            sigStr.draw(at: NSPoint(x: rowRect.maxX - sigSize.width - 8, y: rowRect.minY + 5))

            y += 25
        }

        // Footer link
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: UIStyle.captionFont,
            .foregroundColor: NSColor.controlAccentColor
        ]
        NSAttributedString(string: "Add support for your cooler →", attributes: linkAttrs)
            .draw(at: NSPoint(x: pad, y: 240))
    }
}

/// Studio-grade GitHub Social Preview & Repository Hero Banner (1280x640 pt -> 2560x1280 px Retina)
final class HeroBannerView: NSView {
    override var isFlipped: Bool { true }

    private let leftCard: NSView
    private let rightCard: NSView

    init() {
        let cardW = UIStyle.menuWidth // 330

        // Primary foreground card: Step-Ladder Autopilot v3.1
        let status1 = StatusCardView(width: cardW)
        status1.update(StatusCardView.ViewModel(dieTempC: 52.0, thermalState: .nominal))
        status1.menuEdges = [.top]

        let cooler1 = CoolerPanelView(width: cardW)
        cooler1.update(CoolerPanelView.ViewModel(
            isConnected: true,
            phase: .ready,
            deviceModelName: "REDMAGIC Magnetic Cooler 5 Pro (36W)",
            telemetry: CoolerTelemetry(coldC: 10, hotC: 38, ambientC: 24, fanRPM: 6200),
            mode: .low,
            fanPercent: 40,
            statusDetail: "Auto Tier 1 — Quiet (40%)",
            deviceLooksPoweredOff: false,
            note: nil
        ))

        let coolHeader1 = SectionHeaderRow(width: cardW, title: "Cooling")
        let mode1 = ModeSwitchView(width: cardW)
        mode1.setMode(.auto)
        mode1.panelSegment = .top

        let auto1 = AutoOptionsView(width: cardW)
        auto1.configure(currentTier: .tier1_low, dieTempC: 52.0, isSafetyActive: false)
        auto1.panelSegment = .bottom

        let lightHeader1 = SectionHeaderRow(width: cardW, title: "Light")
        let effect1 = LedEffectPickerView(width: cardW)
        effect1.setSelected(.auto)
        effect1.panelSegment = .only

        let footer1 = MenuFooterRow(width: cardW)
        footer1.menuEdges = [.bottom]

        self.leftCard = MenuPopupContainerView(width: cardW, rows: [
            status1, cooler1, coolHeader1, mode1, auto1, lightHeader1, effect1, footer1
        ])

        // Secondary background card: Multi-Brand Device Picker + RGB
        let devHeader = SectionHeaderRow(width: cardW, title: "Available devices")
        devHeader.menuEdges = [.top]
        let picker = PopulatedDevicePickerRow(width: cardW)
        let lightHeader = SectionHeaderRow(width: cardW, title: "Light")
        let effect = LedEffectPickerView(width: cardW)
        effect.setSelected(.auto)
        effect.panelSegment = .only
        let footer2 = MenuFooterRow(width: cardW)
        footer2.menuEdges = [.bottom]

        self.rightCard = MenuPopupContainerView(width: cardW, rows: [
            devHeader, picker, lightHeader, effect, footer2
        ])

        super.init(frame: NSRect(x: 0, y: 0, width: 1280, height: 640))

        rightCard.frame.origin = CGPoint(x: 914, y: 112)
        leftCard.frame.origin = CGPoint(x: 564, y: 44)

        addSubview(rightCard)
        addSubview(leftCard)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // 1. Deep anodized dark gradient background
        let bgGrad = NSGradient(starting: NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1.0),
                                ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1.0))
        bgGrad?.draw(in: bounds, angle: 35)

        // Subtle cyan radial glow behind the app cards
        let glowRect = NSRect(x: 540, y: -40, width: 760, height: 720)
        let glowGrad = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.0, green: 0.68, blue: 0.95, alpha: 0.18), 0.0),
            (NSColor(calibratedRed: 0.0, green: 0.40, blue: 0.85, alpha: 0.05), 0.5),
            (NSColor.clear, 1.0)
        )
        glowGrad?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

        // 2. Subtle top accent line
        let topBarGrad = NSGradient(colors: [
            NSColor(calibratedRed: 0.0, green: 0.72, blue: 1.0, alpha: 0.85),
            NSColor(calibratedRed: 0.1, green: 0.90, blue: 0.65, alpha: 0.65),
            NSColor.clear
        ])
        topBarGrad?.draw(in: NSRect(x: 0, y: 0, width: 1280, height: 4), angle: 0)

        // 3. Left Column — Brand Identity & Key Features
        let leftX: CGFloat = 56
        var y: CGFloat = 64

        // Brand mark + Version pill
        let iconBox = NSRect(x: leftX, y: y, width: 48, height: 48)
        NSColor(calibratedRed: 0.0, green: 0.68, blue: 0.95, alpha: 0.15).setFill()
        let iconPath = NSBezierPath(roundedRect: iconBox, xRadius: 12, yRadius: 12)
        iconPath.fill()
        NSColor(calibratedRed: 0.0, green: 0.72, blue: 0.98, alpha: 0.45).setStroke()
        iconPath.lineWidth = 1.0
        iconPath.stroke()

        RedMagicLogo.drawR(in: NSRect(x: leftX + 11, y: y + 11, width: 26, height: 26))

        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.85, blue: 1.0, alpha: 1.0),
            .kern: 0.5
        ]
        let badgeStr = NSAttributedString(string: "NATIVE MACOS MENU BAR APP · v3.1", attributes: badgeAttrs)
        let pillRect = NSRect(x: leftX + 62, y: y + 10, width: badgeStr.size().width + 28, height: 28)
        NSColor(white: 1.0, alpha: 0.07).setFill()
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 14, yRadius: 14)
        pillPath.fill()
        NSColor(white: 1.0, alpha: 0.14).setStroke()
        pillPath.stroke()

        badgeStr.draw(at: NSPoint(x: pillRect.minX + 14, y: pillRect.minY + 6))

        y += 70

        // Hero Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 46, weight: .bold),
            .foregroundColor: NSColor.white,
            .kern: -0.8
        ]
        NSAttributedString(string: "Smart Cooler\nControl", attributes: titleAttrs)
            .draw(in: NSRect(x: leftX, y: y, width: 480, height: 116))

        y += 122

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16.5, weight: .regular),
            .foregroundColor: NSColor(white: 0.80, alpha: 1.0)
        ]
        let subText = "Intelligent multi-brand active Peltier (≥ 30W) cooling controller for Apple Silicon MacBooks over Bluetooth LE."
        NSAttributedString(string: subText, attributes: subAttrs)
            .draw(in: NSRect(x: leftX, y: y, width: 472, height: 50))

        y += 66

        // Feature Pills Grid
        let features: [(title: String, detail: String)] = [
            ("Deterministic Step-Ladder", "4 calibrated stages [50°·60°·65°·70°C] with dwell buffer"),
            ("Universal Safety Governor", "Automatic standby shutoff < 36°C against condensation"),
            ("Calibrated Thermal LED", "Apple Silicon Blue → Yellow → Orange → Red chassis gauge"),
            ("Multi-Brand ≥ 30W Catalog", "REDMAGIC 5/6/8 Pro · Black Shark 5 Pro · Flydigi B8X")
        ]

        for feat in features {
            let cardRect = NSRect(x: leftX, y: y, width: 472, height: 50)
            NSColor(white: 1.0, alpha: 0.05).setFill()
            let cPath = NSBezierPath(roundedRect: cardRect, xRadius: 10, yRadius: 10)
            cPath.fill()
            NSColor(white: 1.0, alpha: 0.10).setStroke()
            cPath.lineWidth = 1.0
            cPath.stroke()

            // Cyan accent dot
            let dotRect = NSRect(x: cardRect.minX + 16, y: cardRect.minY + 19, width: 10, height: 10)
            NSColor(calibratedRed: 0.0, green: 0.72, blue: 0.98, alpha: 1.0).setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            let fTitleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            NSAttributedString(string: feat.title, attributes: fTitleAttrs)
                .draw(at: NSPoint(x: cardRect.minX + 36, y: cardRect.minY + 7))

            let fSubAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(white: 0.68, alpha: 1.0)
            ]
            NSAttributedString(string: feat.detail, attributes: fSubAttrs)
                .draw(at: NSPoint(x: cardRect.minX + 36, y: cardRect.minY + 26))

            y += 58
        }

        // Bottom hardware compatibility strip
        let footAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor(white: 0.55, alpha: 1.0)
        ]
        NSAttributedString(string: "Apple Silicon M1 · M2 · M3 · M4 · M5  |  Swift + AppKit + CoreBluetooth", attributes: footAttrs)
            .draw(at: NSPoint(x: leftX, y: 584))

        // 4. Shadows under the two right-hand live UI cards
        for card in [rightCard, leftCard] {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0.0, alpha: 0.75)
            shadow.shadowOffset = NSSize(width: 0, height: -12)
            shadow.shadowBlurRadius = 28
            shadow.set()

            let path = NSBezierPath(roundedRect: card.frame,
                                    xRadius: UIStyle.menuCornerRadius,
                                    yRadius: UIStyle.menuCornerRadius)
            NSColor(white: 0.14, alpha: 1.0).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

func renderImage(view: NSView, to path: String, asJPEG: Bool = false) {
    let darkAppearance = NSAppearance(named: .darkAqua)
    view.appearance = darkAppearance

    let window = NSWindow(
        contentRect: view.bounds,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.appearance = darkAppearance
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = view
    view.layoutSubtreeIfNeeded()

    let scale: CGFloat = 2.0
    let width = view.bounds.width
    let height = view.bounds.height

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Failed to create bitmap rep for \(path)")
        return
    }

    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        print("Failed to create context for \(path)")
        return
    }
    NSGraphicsContext.current = ctx
    darkAppearance?.performAsCurrentDrawingAppearance {
        view.displayIgnoringOpacity(view.bounds, in: ctx)
    }
    NSGraphicsContext.restoreGraphicsState()

    let fileType: NSBitmapImageRep.FileType = asJPEG ? .jpeg : .png
    let props: [NSBitmapImageRep.PropertyKey: Any] = asJPEG ? [.compressionFactor: 0.94] : [:]
    if let data = rep.representation(using: fileType, properties: props) {
        let url = URL(fileURLWithPath: path)
        try? data.write(to: url)
        print("Generated: \(path) (\(Int(width * scale))x\(Int(height * scale)))")
    }
}

func buildAutoScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 52.0, thermalState: .nominal))
    statusCard.menuEdges = [.top]

    let coolerPanel = CoolerPanelView(width: width)
    coolerPanel.update(CoolerPanelView.ViewModel(
        isConnected: true,
        phase: .ready,
        deviceModelName: "REDMAGIC Magnetic Cooler 5 Pro (36W)",
        telemetry: CoolerTelemetry(coldC: 10, hotC: 38, ambientC: 24, fanRPM: 6200),
        mode: .low,
        fanPercent: 40,
        statusDetail: "Auto Tier 1 — Quiet (40%)",
        deviceLooksPoweredOff: false,
        note: nil
    ))

    let coolingHeader = SectionHeaderRow(width: width, title: "Cooling")

    let modeSwitch = ModeSwitchView(width: width)
    modeSwitch.setMode(.auto)
    modeSwitch.panelSegment = .top

    let autoOptions = AutoOptionsView(width: width)
    autoOptions.configure(currentTier: .tier1_low, dieTempC: 52.0, isSafetyActive: false)
    autoOptions.panelSegment = .bottom

    let lightHeader = SectionHeaderRow(width: width, title: "Light")

    let effectPicker = LedEffectPickerView(width: width)
    effectPicker.setSelected(.auto)
    effectPicker.panelSegment = .only

    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")

    let turnOff = MenuActionRow(width: width, title: "Turn Off Cooler", symbol: "power")
    turnOff.panelSegment = .top

    let changeDevice = MenuActionRow(width: width, title: "Change Device…", symbol: "antenna.radiowaves.left.and.right")
    changeDevice.panelSegment = .middle

    let quit = MenuActionRow(width: width, title: "Quit Smart Cooler", symbol: "xmark.circle")
    quit.panelSegment = .bottom

    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]

    let menu = MenuPopupContainerView(width: width, rows: [
        statusCard, coolerPanel, coolingHeader, modeSwitch, autoOptions,
        lightHeader, effectPicker, settingsHeader, turnOff, changeDevice, quit, footer
    ])
    return ShowcaseCanvasView(menuBarTemp: "52°", menuView: menu)
}

func buildTurboScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 74.0, thermalState: .fair))
    statusCard.menuEdges = [.top]

    let coolerPanel = CoolerPanelView(width: width)
    coolerPanel.update(CoolerPanelView.ViewModel(
        isConnected: true,
        phase: .ready,
        deviceModelName: "REDMAGIC VC Cooler 6 Pro+ (40W)",
        telemetry: CoolerTelemetry(coldC: -2, hotC: 48, ambientC: 25, fanRPM: 9600),
        mode: .max,
        fanPercent: 100,
        statusDetail: "Turbo Boost (100%) — Peak Defense",
        deviceLooksPoweredOff: false,
        note: nil
    ))

    let coolingHeader = SectionHeaderRow(width: width, title: "Cooling")

    let modeSwitch = ModeSwitchView(width: width)
    modeSwitch.setMode(.turbo)
    modeSwitch.panelSegment = .top

    let turboStatus = TurboStatusView(width: width)
    turboStatus.panelSegment = .bottom

    let lightHeader = SectionHeaderRow(width: width, title: "Light")

    let effectPicker = LedEffectPickerView(width: width)
    effectPicker.setSelected(.auto)
    effectPicker.panelSegment = .only

    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")

    let turnOff = MenuActionRow(width: width, title: "Turn Off Cooler", symbol: "power")
    turnOff.panelSegment = .top

    let changeDevice = MenuActionRow(width: width, title: "Change Device…", symbol: "antenna.radiowaves.left.and.right")
    changeDevice.panelSegment = .middle

    let quit = MenuActionRow(width: width, title: "Quit Smart Cooler", symbol: "xmark.circle")
    quit.panelSegment = .bottom

    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]

    let menu = MenuPopupContainerView(width: width, rows: [
        statusCard, coolerPanel, coolingHeader, modeSwitch, turboStatus,
        lightHeader, effectPicker, settingsHeader, turnOff, changeDevice, quit, footer
    ])
    return ShowcaseCanvasView(menuBarTemp: "74°", menuView: menu)
}

func buildManualScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 48.0, thermalState: .nominal))
    statusCard.menuEdges = [.top]

    let coolerPanel = CoolerPanelView(width: width)
    coolerPanel.update(CoolerPanelView.ViewModel(
        isConnected: true,
        phase: .ready,
        deviceModelName: "Black Shark MagCooler 5 Pro (35W)",
        telemetry: CoolerTelemetry(coldC: 6, hotC: 42, ambientC: 24, fanRPM: 7800),
        mode: .medium,
        fanPercent: 80,
        statusDetail: "Manual Cooling (80%)",
        deviceLooksPoweredOff: false,
        note: nil
    ))

    let coolingHeader = SectionHeaderRow(width: width, title: "Cooling")

    let modeSwitch = ModeSwitchView(width: width)
    modeSwitch.setMode(.manual)
    modeSwitch.panelSegment = .top

    let coolingSlider = CoolingSliderView(width: width)
    coolingSlider.setStep(6) // 80% fan
    coolingSlider.panelSegment = .middle

    let manualTimer = ManualTimerView(width: width)
    manualTimer.setTimeout(.oneHour)
    manualTimer.setRemaining("59m")
    manualTimer.panelSegment = .bottom

    let lightHeader = SectionHeaderRow(width: width, title: "Light")

    let effectPicker = LedEffectPickerView(width: width)
    effectPicker.setSelected(.breath)
    effectPicker.panelSegment = .top

    let breathToggle = BreathStyleToggleView(width: width)
    breathToggle.setStyle(.monochrome)
    breathToggle.panelSegment = .middle

    let colorPicker = HueSpectrumPickerView(width: width)
    colorPicker.setHue(0.55)
    colorPicker.panelSegment = .bottom

    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")

    let turnOff = MenuActionRow(width: width, title: "Turn Off Cooler", symbol: "power")
    turnOff.panelSegment = .top

    let changeDevice = MenuActionRow(width: width, title: "Change Device…", symbol: "antenna.radiowaves.left.and.right")
    changeDevice.panelSegment = .middle

    let quit = MenuActionRow(width: width, title: "Quit Smart Cooler", symbol: "xmark.circle")
    quit.panelSegment = .bottom

    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]

    let menu = MenuPopupContainerView(width: width, rows: [
        statusCard, coolerPanel, coolingHeader, modeSwitch, coolingSlider, manualTimer,
        lightHeader, effectPicker, breathToggle, colorPicker,
        settingsHeader, turnOff, changeDevice, quit, footer
    ])
    return ShowcaseCanvasView(menuBarTemp: "48°", menuView: menu)
}

func buildDevicePickerScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 42.0, thermalState: .nominal))
    statusCard.menuEdges = [.top]

    let devicesHeader = SectionHeaderRow(width: width, title: "Available devices")
    let pickerRow = PopulatedDevicePickerRow(width: width)

    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")
    let quit = MenuActionRow(width: width, title: "Quit Smart Cooler", symbol: "xmark.circle")
    quit.panelSegment = .only

    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]

    let menu = MenuPopupContainerView(width: width, rows: [
        statusCard, devicesHeader, pickerRow, settingsHeader, quit, footer
    ])
    return ShowcaseCanvasView(menuBarTemp: "42°", menuView: menu)
}

@main
struct ScreenshotGenerator {
    static func main() {
        _ = NSApplication.shared
        UserDefaults.standard.set("MacBook Air", forKey: Config.Key.cachedMacModel)

        let width = UIStyle.menuWidth // 330
        let outDir = "/Users/user/Documents/redmagic-cooler-mac/docs/images"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let autoView = buildAutoScreenshot(width: width)
        let turboView = buildTurboScreenshot(width: width)
        let manualView = buildManualScreenshot(width: width)
        let devicePickerView = buildDevicePickerScreenshot(width: width)
        let bannerView = HeroBannerView()

        renderImage(view: autoView, to: "\(outDir)/screenshot_auto_stepladder.png")
        renderImage(view: autoView, to: "\(outDir)/screenshot_auto_smartmax.png")
        renderImage(view: turboView, to: "\(outDir)/screenshot_turbo.png")
        renderImage(view: turboView, to: "\(outDir)/screenshot_auto_balanced.png")
        renderImage(view: manualView, to: "\(outDir)/screenshot_manual.png")
        renderImage(view: devicePickerView, to: "\(outDir)/screenshot_device_picker.png")
        renderImage(view: bannerView, to: "\(outDir)/banner.jpg", asJPEG: true)

        let defaultPreview = "\(outDir)/screenshot_auto_stepladder.png"
        let legacyTarget = "/Users/user/Documents/redmagic-cooler-mac/docs/screenshot.png"
        if FileManager.default.fileExists(atPath: defaultPreview) {
            try? FileManager.default.removeItem(atPath: legacyTarget)
            try? FileManager.default.copyItem(atPath: defaultPreview, toPath: legacyTarget)
        }

        print("All Retina screenshots + Hero Banner generated successfully!")
    }
}
