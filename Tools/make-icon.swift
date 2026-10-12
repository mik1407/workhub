import Cocoa

// Draws the WorkHub app icon (orange tile, navy briefcase holding colored app tiles)
// and writes Resources/AppIcon.icns with every size macOS needs.
// Usage, from the repository root: swift Tools/make-icon.swift

let canvas: CGFloat = 1024
let body: CGFloat = 824            // macOS icon grid: 824 px tile centered on a 1024 px canvas
let unit = body / 120              // the design is drawn on a 120 × 120 grid

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// Rectangle on the 120-unit grid (origin top-left) → canvas coordinates.
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: (canvas - body) / 2 + x * unit, y: (canvas - body) / 2 + y * unit, width: w * unit, height: h * unit)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, _ fill: UInt32) {
    color(fill).setFill()
    NSBezierPath(roundedRect: rect(x, y, w, h), xRadius: radius * unit, yRadius: radius * unit).fill()
}

func render(size: Int) -> NSBitmapImageRep {
    // sRGB bitmap: the colors below are sRGB, so they are written as they are, with no conversion.
    let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    // Top-left origin, so the drawing reads like the 120-unit design.
    cg.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    cg.translateBy(x: 0, y: canvas)
    cg.scaleBy(x: 1, y: -1)

    // Tile with a soft shadow, as on the macOS icon grid
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: 10)   // flipped context: positive = down
    shadow.set()
    roundedRect(0, 0, 120, 120, radius: 27, 0xe5713a)
    NSGraphicsContext.restoreGraphicsState()

    // Briefcase handle
    let handle = NSBezierPath()
    handle.move(to: rect(46, 38, 0, 0).origin)
    handle.line(to: rect(46, 32, 0, 0).origin)
    handle.appendArc(withCenter: rect(52, 32, 0, 0).origin, radius: 6 * unit, startAngle: 180, endAngle: 270)
    handle.line(to: rect(68, 26, 0, 0).origin)
    handle.appendArc(withCenter: rect(68, 32, 0, 0).origin, radius: 6 * unit, startAngle: 270, endAngle: 360)
    handle.line(to: rect(74, 38, 0, 0).origin)
    handle.lineWidth = 7 * unit
    color(0x0f1a2e).setStroke()
    handle.stroke()

    // Briefcase body and the app tiles it holds
    roundedRect(20, 38, 80, 58, radius: 11, 0x0f1a2e)
    let tiles: [(CGFloat, CGFloat, UInt32)] = [
        (34, 52, 0xea4335), (53, 52, 0x25d366), (72, 52, 0x2f9be9),
        (34, 71, 0xf2b84b), (53, 71, 0xe8ecf3), (72, 71, 0xe01e5a),
    ]
    for (x, y, fill) in tiles { roundedRect(x, y, 14, 14, radius: 4, fill) }

    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: cg.makeImage()!)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = render(size: points * scale).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Written: \(output.path)" : "iconutil failed")
exit(iconutil.terminationStatus)
