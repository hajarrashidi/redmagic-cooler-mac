import AppKit
import Foundation

final class MenuContainerView: NSView {
    override var isFlipped: Bool { true }
    
    init(width: CGFloat, rows: [NSView]) {
        var totalHeight: CGFloat = 0
        for r in rows {
            totalHeight += r.frame.height
        }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        
        var y: CGFloat = 0
        for r in rows {
            r.frame.origin = CGPoint(x: 0, y: y)
            addSubview(r)
            y += r.frame.height
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class CanvasView: NSView {
    override var isFlipped: Bool { true }
    
    init(contentView: NSView, pad: CGFloat = 36) {
        let w = contentView.bounds.width + pad * 2
        let h = contentView.bounds.height + pad * 2
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
        wantsLayer = true
        
        // Dark translucent gradient backdrop
        layer?.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0).cgColor
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        
        contentView.frame.origin = CGPoint(x: pad, y: pad)
        contentView.wantsLayer = true
        contentView.layer?.shadowColor = NSColor.black.cgColor
        contentView.layer?.shadowOpacity = 0.55
        contentView.layer?.shadowOffset = CGSize(width: 0, height: -8)
        contentView.layer?.shadowRadius = 18
        
        addSubview(contentView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

func renderPNG(view: NSView, to path: String) {
    view.appearance = NSAppearance(named: .darkAqua)
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
    ctx.cgContext.scaleBy(x: scale, y: scale)
    view.displayIgnoringOpacity(view.bounds, in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    
    if let data = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: path)
        try? data.write(to: url)
        print("Generated: \(path) (\(Int(width * scale))x\(Int(height * scale)))")
    }
}

func buildSmartMaxScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 42.0, thermalState: .nominal))
    statusCard.menuEdges = [.top]
    
    let coolerPanel = CoolerPanelView(width: width)
    coolerPanel.update(CoolerPanelView.ViewModel(
        isConnected: true,
        phase: .ready,
        deviceModelName: "REDMAGIC Magnetic Cooler 5 Pro (36W)",
        telemetry: CoolerTelemetry(coldC: 14, hotC: 38, ambientC: 24, fanRPM: 6100),
        mode: .low,
        fanPercent: 40,
        statusDetail: "Active Cooling (40%)",
        deviceLooksPoweredOff: false,
        note: nil
    ))
    
    let coolingHeader = SectionHeaderRow(width: width, title: "Cooling")
    
    let modeSwitch = ModeSwitchView(width: width)
    modeSwitch.setMode(.auto)
    modeSwitch.panelSegment = .top
    
    let autoOptions = AutoOptionsView(width: width)
    autoOptions.configure(engageC: 52.0, shutoffC: 38.0, minFanPercent: 40, profile: .smartMax)
    autoOptions.panelSegment = .bottom
    
    let lightHeader = SectionHeaderRow(width: width, title: "Light")
    
    let effectPicker = LedEffectPickerView(width: width)
    effectPicker.setSelected(.auto)
    effectPicker.panelSegment = .only
    
    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")
    
    let turnOff = MenuActionRow(width: width, title: "Turn Off", symbol: "power")
    turnOff.panelSegment = .top
    
    let changeDevice = MenuActionRow(width: width, title: "Change Device…", symbol: "antenna.radiowaves.left.and.right")
    changeDevice.panelSegment = .middle
    
    let quit = MenuActionRow(width: width, title: "Turn Off & Quit", symbol: "power.circle")
    quit.panelSegment = .bottom
    
    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]
    
    let rows: [NSView] = [
        statusCard,
        coolerPanel,
        coolingHeader,
        modeSwitch,
        autoOptions,
        lightHeader,
        effectPicker,
        settingsHeader,
        turnOff,
        changeDevice,
        quit,
        footer
    ]
    
    let menu = MenuContainerView(width: width, rows: rows)
    return CanvasView(contentView: menu)
}

func buildBalancedScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 48.0, thermalState: .nominal))
    statusCard.menuEdges = [.top]
    
    let coolerPanel = CoolerPanelView(width: width)
    coolerPanel.update(CoolerPanelView.ViewModel(
        isConnected: true,
        phase: .ready,
        deviceModelName: "REDMAGIC Magnetic Cooler 5 Pro (36W)",
        telemetry: CoolerTelemetry(coldC: 11, hotC: 42, ambientC: 25, fanRPM: 7400),
        mode: .medium,
        fanPercent: 70,
        statusDetail: "Active Cooling (70%)",
        deviceLooksPoweredOff: false,
        note: nil
    ))
    
    let coolingHeader = SectionHeaderRow(width: width, title: "Cooling")
    
    let modeSwitch = ModeSwitchView(width: width)
    modeSwitch.setMode(.auto)
    modeSwitch.panelSegment = .top
    
    let autoOptions = AutoOptionsView(width: width)
    autoOptions.configure(engageC: 50.0, shutoffC: 38.0, minFanPercent: 40, profile: .balanced)
    autoOptions.panelSegment = .bottom
    
    let lightHeader = SectionHeaderRow(width: width, title: "Light")
    
    let effectPicker = LedEffectPickerView(width: width)
    effectPicker.setSelected(.auto)
    effectPicker.panelSegment = .only
    
    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")
    
    let turnOff = MenuActionRow(width: width, title: "Turn Off", symbol: "power")
    turnOff.panelSegment = .top
    
    let changeDevice = MenuActionRow(width: width, title: "Change Device…", symbol: "antenna.radiowaves.left.and.right")
    changeDevice.panelSegment = .middle
    
    let quit = MenuActionRow(width: width, title: "Turn Off & Quit", symbol: "power.circle")
    quit.panelSegment = .bottom
    
    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]
    
    let rows: [NSView] = [
        statusCard,
        coolerPanel,
        coolingHeader,
        modeSwitch,
        autoOptions,
        lightHeader,
        effectPicker,
        settingsHeader,
        turnOff,
        changeDevice,
        quit,
        footer
    ]
    
    let menu = MenuContainerView(width: width, rows: rows)
    return CanvasView(contentView: menu)
}

func buildManualScreenshot(width: CGFloat) -> NSView {
    let statusCard = StatusCardView(width: width)
    statusCard.update(StatusCardView.ViewModel(dieTempC: 44.0, thermalState: .nominal))
    statusCard.menuEdges = [.top]
    
    let coolerPanel = CoolerPanelView(width: width)
    coolerPanel.update(CoolerPanelView.ViewModel(
        isConnected: true,
        phase: .ready,
        deviceModelName: "REDMAGIC Magnetic Cooler 5 Pro (36W)",
        telemetry: CoolerTelemetry(coldC: 9, hotC: 44, ambientC: 25, fanRPM: 8900),
        mode: .max,
        fanPercent: 100,
        statusDetail: "Active Cooling (100%)",
        deviceLooksPoweredOff: false,
        note: nil
    ))
    
    let coolingHeader = SectionHeaderRow(width: width, title: "Cooling")
    
    let modeSwitch = ModeSwitchView(width: width)
    modeSwitch.setMode(.manual)
    modeSwitch.panelSegment = .top
    
    let coolingSlider = CoolingSliderView(width: width)
    coolingSlider.setStep(10) // Max
    coolingSlider.panelSegment = .middle
    
    let manualTimer = ManualTimerView(width: width)
    manualTimer.setTimeout(.oneHour)
    manualTimer.setRemaining("58m left")
    manualTimer.panelSegment = .bottom
    
    let lightHeader = SectionHeaderRow(width: width, title: "Light")
    
    let effectPicker = LedEffectPickerView(width: width)
    effectPicker.setSelected(.stroke)
    effectPicker.panelSegment = .top
    
    let breathToggle = BreathStyleToggleView(width: width)
    breathToggle.setStyle(.colorful)
    breathToggle.panelSegment = .bottom
    
    let settingsHeader = SectionHeaderRow(width: width, title: "Settings")
    
    let turnOff = MenuActionRow(width: width, title: "Turn Off", symbol: "power")
    turnOff.panelSegment = .top
    
    let changeDevice = MenuActionRow(width: width, title: "Change Device…", symbol: "antenna.radiowaves.left.and.right")
    changeDevice.panelSegment = .middle
    
    let quit = MenuActionRow(width: width, title: "Turn Off & Quit", symbol: "power.circle")
    quit.panelSegment = .bottom
    
    let footer = MenuFooterRow(width: width)
    footer.menuEdges = [.bottom]
    
    let rows: [NSView] = [
        statusCard,
        coolerPanel,
        coolingHeader,
        modeSwitch,
        coolingSlider,
        manualTimer,
        lightHeader,
        effectPicker,
        breathToggle,
        settingsHeader,
        turnOff,
        changeDevice,
        quit,
        footer
    ]
    
    let menu = MenuContainerView(width: width, rows: rows)
    return CanvasView(contentView: menu)
}

@main
struct ScreenshotGenerator {
    static func main() {
        let width = UIStyle.menuWidth // 330
        
        let outDir = "/Users/user/Documents/redmagic-cooler-mac/docs/images"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        
        let smartMaxView = buildSmartMaxScreenshot(width: width)
        renderPNG(view: smartMaxView, to: "\(outDir)/screenshot_auto_smartmax.png")
        
        let balancedView = buildBalancedScreenshot(width: width)
        renderPNG(view: balancedView, to: "\(outDir)/screenshot_auto_balanced.png")
        
        let manualView = buildManualScreenshot(width: width)
        renderPNG(view: manualView, to: "\(outDir)/screenshot_manual.png")
        
        // Copy the original screenshot.png to maintain backwards compatibility
        let defaultPreview = "\(outDir)/screenshot_auto_smartmax.png"
        let legacyTarget = "/Users/user/Documents/redmagic-cooler-mac/docs/screenshot.png"
        if FileManager.default.fileExists(atPath: defaultPreview) {
            try? FileManager.default.removeItem(atPath: legacyTarget)
            try? FileManager.default.copyItem(atPath: defaultPreview, toPath: legacyTarget)
        }
        
        print("All screenshots generated successfully!")
    }
}
