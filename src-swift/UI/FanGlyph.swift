import AppKit

/// Draws a stylised cooling fan: a hub plus swept blades, wrapped in an icy
/// "frost" glow whose intensity grows with the cooling zone.
///
/// The caller animates it by advancing `angleRadians`. An `off` zone is drawn
/// dim, static and without frost — not spinning reads as off at a glance.
enum FanGlyph {

    static let bladeCount = 5

    /// Frost opacity per zone, indexed by `CoolingMode.Zone.rawValue`.
    private static let frostAlpha: [CGFloat] = [0.0, 0.18, 0.30, 0.45]
    /// How far the glow extends past the blades, per zone step.
    private static let glowGrowthPerZone: CGFloat = 0.12

    /// Blade extent and hub size, as fractions of the glyph radius.
    private static let bladeRadiusFraction: CGFloat = 0.82
    private static let hubRadiusFraction: CGFloat = 0.22

    /// - Parameters:
    ///   - rect: bounding square for the whole glyph, frost included.
    ///   - angleRadians: current rotation of the blades.
    ///   - color: blade tint — the active LED colour, or grey when off.
    ///   - zone: drives frost intensity and whether the glyph reads as running.
    static func draw(in rect: NSRect, angleRadians: CGFloat,
                     color: NSColor, zone: CoolingMode.Zone) {
        let level = zone.rawValue
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // ── Frost glow (behind the blades) ──────────────────────────────────
        if level > 0 {
            let alpha = frostAlpha[min(level, frostAlpha.count - 1)]
            let frostColor = NSColor(calibratedRed: 0.55, green: 0.85, blue: 1.0, alpha: alpha)
            let glowR = radius * (1.0 + glowGrowthPerZone * CGFloat(level))
            if let gradient = NSGradient(colors: [frostColor,
                                                  frostColor.withAlphaComponent(0)]) {
                NSGraphicsContext.saveGraphicsState()
                gradient.draw(fromCenter: center, radius: 0,
                              toCenter: center, radius: glowR, options: [])
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        let bladeColor = (level == 0) ? NSColor.tertiaryLabelColor : color
        let bladeR = radius * bladeRadiusFraction

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byRadians: angleRadians)
        transform.concat()

        for i in 0..<bladeCount {
            let a = CGFloat(i) / CGFloat(bladeCount) * 2 * .pi
            let blade = NSBezierPath()
            // A curved teardrop blade sweeping out from the hub.
            blade.move(to: NSPoint(x: bladeR * 0.18 * cos(a), y: bladeR * 0.18 * sin(a)))
            let tip = NSPoint(x: bladeR * cos(a + 0.10), y: bladeR * sin(a + 0.10))
            let ctrl1 = NSPoint(x: bladeR * 0.55 * cos(a - 0.45), y: bladeR * 0.55 * sin(a - 0.45))
            let ctrl2 = NSPoint(x: bladeR * 0.95 * cos(a - 0.15), y: bladeR * 0.95 * sin(a - 0.15))
            blade.curve(to: tip, controlPoint1: ctrl1, controlPoint2: ctrl2)
            let back1 = NSPoint(x: bladeR * 0.85 * cos(a + 0.55), y: bladeR * 0.85 * sin(a + 0.55))
            let back2 = NSPoint(x: bladeR * 0.40 * cos(a + 0.55), y: bladeR * 0.40 * sin(a + 0.55))
            blade.curve(to: NSPoint(x: 0, y: 0), controlPoint1: back1, controlPoint2: back2)
            blade.close()
            bladeColor.withAlphaComponent(level == 0 ? 0.6 : 0.95).setFill()
            blade.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Hub
        let hubR = radius * hubRadiusFraction
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - hubR, y: center.y - hubR,
                                              width: hubR * 2, height: hubR * 2))
        // A lightened hub reads as a highlight against the spinning blades.
        let hubColor = (level == 0)
            ? NSColor.tertiaryLabelColor
            : bladeColor.blended(withFraction: 0.3, of: .white) ?? bladeColor
        hubColor.setFill()
        hub.fill()
    }
}
