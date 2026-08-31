import AppKit

/// The RedMagic "R" mark, drawn as a vector path rather than shipped as an
/// asset so it stays crisp at any size and can be recoloured — including as a
/// menu-bar template image, which the system tints to match the user's theme.
///
/// Path coordinates are expressed on a 20×20 grid and scaled to the target
/// rect, in a y-down (flipped) space.
enum RedMagicLogo {
    static let brandRed = NSColor(red: 0.89, green: 0.11, blue: 0.13, alpha: 1)

    /// NSImage of the R mark. Pass `template: true` for a menu-bar icon (system tints it).
    static func image(size: CGFloat, template: Bool = false) -> NSImage {
        let color: NSColor = template ? .black : brandRed
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            drawR(in: rect, color: color)
            return true
        }
        img.isTemplate = template
        return img
    }

    /// Draw the R mark into the current graphics context.
    /// Designed for a y-down (flipped) coordinate system.
    static func drawR(in rect: NSRect, color: NSColor = brandRed) {
        let w = rect.width, h = rect.height
        let ox = rect.minX, oy = rect.minY
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: ox + x / 20 * w, y: oy + y / 20 * h)
        }

        let path = NSBezierPath()
        path.windingRule = .evenOdd

        // Outer R — clockwise in y-down space
        path.move(to: pt( 0,  0))
        path.line(to: pt(14,  0))
        path.line(to: pt(20,  5))
        path.line(to: pt(20, 11))
        path.line(to: pt(14, 14))
        path.line(to: pt(20, 20))
        path.line(to: pt(13, 20))
        path.line(to: pt( 8, 14))
        path.line(to: pt( 5, 14))
        path.line(to: pt( 5, 20))
        path.line(to: pt( 0, 20))
        path.close()

        // Bowl cutout — evenOdd rule punches this as a hole
        path.move(to: pt( 5,  3))
        path.line(to: pt(13,  3))
        path.line(to: pt(16,  6))
        path.line(to: pt(15, 11))
        path.line(to: pt( 5, 11))
        path.close()

        color.setFill()
        path.fill()
    }
}

/// View wrapper for the mark. Exists mainly to flip the coordinate space, which
/// `drawR` assumes.
final class RedMagicLogoView: NSView {
    var color: NSColor = RedMagicLogo.brandRed

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RedMagicLogo.drawR(in: bounds, color: color)
    }
}
