import AppKit

/// The Smart Cooler Control "S" mark, drawn as a vector path rather than shipped
/// as a raster asset so it stays crisp at any size and dynamically recolours
/// with the Mac thermal state.
///
/// Path coordinates are expressed on a 20×20 grid and scaled to the target
/// rect, in a y-down (flipped) space.
enum RedMagicLogo {
    /// Electric Ice Cyan — the signature colour of Smart Cooler Control.
    static let brandCyan = NSColor(red: 0.0, green: 0.82, blue: 1.0, alpha: 1.0)
    static let brandRed  = brandCyan

    /// An `NSImage` of the "S" mark, drawn in its final colour.
    static func image(size: CGFloat, color: NSColor = brandCyan) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            drawS(in: rect, color: color)
            return true
        }
    }

    /// Backwards-compatible alias for existing call sites.
    static func drawR(in rect: NSRect, color: NSColor = brandCyan) {
        drawS(in: rect, color: color)
    }

    /// Draws the modern aerodynamic "S" mark into the current graphics context.
    /// Designed for a y-down (flipped) coordinate system.
    static func drawS(in rect: NSRect, color: NSColor = brandCyan) {
        let w = rect.width, h = rect.height
        let ox = rect.minX, oy = rect.minY
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: ox + x / 20 * w, y: oy + y / 20 * h)
        }

        let path = NSBezierPath()
        path.move(to: pt(5.0, 1.5))
        path.line(to: pt(18.5, 1.5))
        path.line(to: pt(18.5, 6.0))
        path.line(to: pt(6.5, 6.0))
        path.line(to: pt(6.5, 9.0))
        path.line(to: pt(18.5, 9.0))
        path.line(to: pt(18.5, 16.5))
        path.line(to: pt(15.0, 20.0))
        path.line(to: pt(1.5, 20.0))
        path.line(to: pt(1.5, 15.5))
        path.line(to: pt(13.5, 15.5))
        path.line(to: pt(13.5, 12.5))
        path.line(to: pt(1.5, 12.5))
        path.line(to: pt(1.5, 5.0))
        path.close()

        color.setFill()
        path.fill()
    }
}
