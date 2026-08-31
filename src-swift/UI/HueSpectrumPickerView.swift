import AppKit

/// A continuous rainbow bar — click or drag anywhere to pick a hue.
///
/// Replaces an earlier fixed-swatch picker; the cooler accepts arbitrary RGB,
/// so there was no reason to ration the choices.
final class HueSpectrumPickerView: NSView {

    /// Reports the chosen hue in 0…1, continuously during a drag.
    var onSelect: ((Double) -> Void)?

    private(set) var hue: CGFloat = 0

    private let hPad = UIStyle.hPad
    private let barTop: CGFloat = 24
    private let barHeight: CGFloat = 16
    /// How far the thumb overhangs the bar on each side.
    private let thumbOverhang: CGFloat = 3

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 52))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Sets the displayed hue without firing `onSelect`.
    func setHue(_ hue: Double) {
        let clamped = CGFloat(hue.clamped(to: 0...1))
        guard clamped != self.hue else { return }
        self.hue = clamped
        needsDisplay = true
    }

    private var barRect: NSRect {
        NSRect(x: hPad, y: barTop, width: bounds.width - hPad * 2, height: barHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        UIStyle.drawSectionHeader("COLOR", at: NSPoint(x: hPad, y: 4))

        // Hex readout, right-aligned against the header.
        let hex = UIStyle.text(RGB(hue: Double(hue)).hexString,
                               UIStyle.captionFont, .secondaryLabelColor)
        hex.draw(at: NSPoint(x: bounds.width - hPad - hex.size().width, y: 4))

        drawSpectrum()
        drawThumb()
    }

    private func drawSpectrum() {
        let bar = barRect
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSBezierPath(roundedRect: bar,
                     xRadius: barHeight / 2, yRadius: barHeight / 2).addClip()
        // 13 stops approximate a continuous wheel closely enough at this size.
        let stops = stride(from: 0.0, through: 1.0, by: 1.0 / 12.0).map {
            NSColor(hue: CGFloat($0), saturation: 1, brightness: 1, alpha: 1)
        }
        NSGradient(colors: stops)?.draw(in: bar, angle: 0)
    }

    private func drawThumb() {
        let bar = barRect
        let radius = barHeight / 2 + thumbOverhang
        let center = bar.minX + hue * bar.width
        let rect = NSRect(x: center - radius, y: bar.midY - radius,
                          width: radius * 2, height: radius * 2)

        RGB(hue: Double(hue)).nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let ring = NSBezierPath(ovalIn: rect)
        ring.lineWidth = 2.5
        NSColor.white.setStroke()
        ring.stroke()
    }

    // ── Interaction ──────────────────────────────────────────────────────────

    override func mouseDown(with event: NSEvent) { updateHue(from: event) }
    override func mouseDragged(with event: NSEvent) { updateHue(from: event) }

    private func updateHue(from event: NSEvent) {
        let bar = barRect
        let x = convert(event.locationInWindow, from: nil).x
        hue = ((x - bar.minX) / bar.width).clamped(to: 0...1)
        needsDisplay = true
        onSelect?(Double(hue))
    }
}
