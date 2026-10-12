import Cocoa
import WebKit

// Builds Resources/AppIcon.icns from Tools/AppIcon.svg (1024 × 1024 rounded tile).
// The SVG is rendered with WebKit (gradients and filters included), placed on the macOS icon grid
// (824 px tile centered on a 1024 px canvas) with a soft shadow, then rendered at every size macOS needs.
// Usage, from the repository root: swift Tools/make-icon.swift

let canvas: CGFloat = 1024
let body: CGFloat = 824
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgURL = root.appendingPathComponent("Tools/AppIcon.svg")
guard let svg = try? String(contentsOf: svgURL, encoding: .utf8) else {
    print("Tools/AppIcon.svg not found: run this from the repository root")
    exit(1)
}

/// Renders the SVG at 1024 × 1024 points with a transparent background.
final class SVGRenderer: NSObject, WKNavigationDelegate {
    private let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: canvas, height: canvas))
    private var completion: ((NSImage?) -> Void)?

    func render(_ svg: String, completion: @escaping (NSImage?) -> Void) {
        self.completion = completion
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        let html = """
        <!doctype html><html><head><style>html,body{margin:0;background:transparent}svg{display:block;width:\(Int(canvas))px;height:\(Int(canvas))px}</style></head><body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
        config.snapshotWidth = NSNumber(value: Double(canvas))
        webView.takeSnapshot(with: config) { image, _ in self.completion?(image) }
    }
}

func render(_ artwork: NSImage, size: Int) -> NSBitmapImageRep {
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

func writeIcon(from artwork: NSImage) -> Int32 {
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
            let png = render(artwork, size: points * scale).representation(using: .png, properties: [:])!
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
    return iconutil.terminationStatus
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = SVGRenderer()
renderer.render(svg) { image in
    guard let image = image else {
        print("Couldn't render Tools/AppIcon.svg")
        exit(1)
    }
    exit(writeIcon(from: image))
}
app.run()
