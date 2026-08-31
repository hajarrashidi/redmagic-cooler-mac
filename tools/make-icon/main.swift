import AppKit

// Renders the app icon into Resources/AppIcon.icns.
//
// The mark is drawn from the same vector path the app uses at runtime
// (RedMagicLogo), so the icon can never drift from the in-app logo. Run it via
// tools/make-icon.sh, which links this against the app's own source.
//
// Layout follows Apple's macOS icon grid: the artwork sits on a rounded square
// inset from the canvas, with a corner radius just under a quarter of its side.

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

/// Fraction of the canvas the rounded square occupies. Apple's macOS app icons
/// leave a margin so they optically match system icons in the Dock.
let squircleInset: CGFloat = 0.06
/// Corner radius as a fraction of the square's side.
let cornerFraction: CGFloat = 0.2237
/// How much of the square's width the "R" spans.
let markFraction: CGFloat = 0.52

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
        let inset = size * squircleInset
        let square = NSRect(x: inset, y: inset,
                            width: size - inset * 2, height: size - inset * 2)
        let radius = square.width * cornerFraction

        // Brand-red rounded square, with a subtle vertical sheen so the icon
        // doesn't read as a flat sticker at large sizes.
        let plate = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)
        let top = NSColor(red: 0.95, green: 0.20, blue: 0.22, alpha: 1)
        let bottom = NSColor(red: 0.80, green: 0.07, blue: 0.10, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        plate.addClip()
        NSGradient(starting: top, ending: bottom)?.draw(in: square, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // White mark, centred on the plate.
        let markWidth = square.width * markFraction
        let mark = NSRect(x: square.midX - markWidth / 2,
                          y: square.midY - markWidth / 2,
                          width: markWidth, height: markWidth)
        RedMagicLogo.drawR(in: mark, color: .white)
        return true
    }
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    // Render into an explicitly sized bitmap so the output is exactly N×N
    // device pixels regardless of the display's backing scale.
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        throw NSError(domain: "make-icon", code: 1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 2)
    }
    try data.write(to: url)
}

// ── Emit the iconset ─────────────────────────────────────────────────────────

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) pairs iconutil expects.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let pixels = variant.points * variant.scale
    let suffix = variant.scale == 2 ? "@2x" : ""
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try writePNG(drawIcon(size: CGFloat(pixels)), pixels: pixels,
                 to: iconset.appendingPathComponent(name))
}

// ── Pack it ──────────────────────────────────────────────────────────────────

let output = URL(fileURLWithPath: outputPath)
try? fm.createDirectory(at: output.deletingLastPathComponent(),
                        withIntermediateDirectories: true)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

try? fm.removeItem(at: iconset)
print("wrote \(outputPath)")
