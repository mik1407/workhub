import Cocoa

// Builds Resources/AppIcon.icns from Tools/AppIcon-artwork.png (1024 px rounded tile, transparent corners).
// The artwork is placed on the macOS icon grid (824 px tile centered on a 1024 px canvas) with a soft shadow,
// then rendered at every size macOS needs.
// Usage, from the repository root: swift Tools/make-icon.swift

let canvas: CGFloat = 1024
let body: CGFloat = 824

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard let artwork = NSImage(contentsOf: root.appendingPathComponent("Tools/AppIcon-artwork.png")) else {
    print("Tools/AppIcon-artwork.png not found: run this from the repository root")
    exit(1)
}

func render(size: Int) -> NSBitmapImageRep {
    // sRGB bitmap: the artwork is sRGB, so its colors are written as they are, with no conversion.
    let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    cg.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    let inset = (canvas - body) / 2
    artwork.draw(in: NSRect(x: inset, y: inset, width: body, height: body))

    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: cg.makeImage()!)
}

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
