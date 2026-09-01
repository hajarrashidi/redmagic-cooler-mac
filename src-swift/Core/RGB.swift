import AppKit

/// A 24-bit colour in the form the cooler's light characteristic expects.
///
/// Exists so LED colour has one representation across the app. Previously the
/// autopilot carried its own hand-rolled HSV→RGB conversion while the colour
/// picker used AppKit's, which meant the same hue could produce two slightly
/// different byte triples depending on which path wrote it.
struct RGB: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Full-saturation, full-brightness colour for a hue in 0…1.
    init(hue: Double) {
        let color = NSColor(hue: CGFloat(hue.clamped(to: 0...1)),
                            saturation: 1, brightness: 1, alpha: 1)
            .usingColorSpace(.deviceRGB) ?? .red
        // Clamped before conversion: colorspace mapping can leave a component
        // a hair outside 0…1, and `UInt8.init` traps on the excursion.
        func byte(_ component: CGFloat) -> UInt8 {
            UInt8((Double(component) * 255).rounded().clamped(to: 0...255))
        }
        self.init(r: byte(color.redComponent),
                  g: byte(color.greenComponent),
                  b: byte(color.blueComponent))
    }

    var nsColor: NSColor {
        NSColor(deviceRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: 1)
    }

    /// `#RRGGBB`, for the colour picker's readout.
    var hexString: String { String(format: "#%02X%02X%02X", r, g, b) }

    /// Wire order for the light characteristic's colour bytes.
    var bytes: [UInt8] { [r, g, b] }
}
