import Cocoa

/// Makes the service icons in the sidebar look consistent.
/// Favicons come in different shapes: some have a solid background (a colored square or circle),
/// others are just the symbol on transparency. Here they all become solid tiles of the same shape:
/// - icon whose background reaches its corners: the icon itself covers the whole tile, so gradients
///   and textures in the background stay seamless;
/// - icon with a smaller background (circle, rounded square): the background color extends to the tile edges;
/// - symbol only: white tile.
/// The symbol always takes up the same share of the tile, unless covering the tile requires a larger one.
enum IconStyle {
    private static let size = 128                // side in pixels used for analysis and output
    private static let glyphFill: CGFloat = 0.58 // longest side of the symbol / side of the tile
    // Favicons are sRGB: analysis and output use the same space, so colors stay true to the website's icon.
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private typealias RGB = (r: Int, g: Int, b: Int)
    private struct Box { var left: Int; var top: Int; var width: Int; var height: Int }
    private struct Raster { let bytes: [UInt8]; let image: CGImage }

    static func normalize(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let raster = rasterize(source, background: nil),
              let shape = shapeBox(raster.bytes) else { return image }

        let background = backgroundColor(raster.bytes, shape: shape)
        let glyph = background.flatMap { glyphBox(raster.bytes, background: $0) } ?? shape
        let fill: RGB = background ?? (255, 255, 255)
        let fullBleed = background != nil && cornersOpaque(raster.bytes, shape: shape)

        // Icon flattened onto its own background: no halos on the edges when it is scaled up.
        guard let flat = rasterize(source, background: fill),
              let tile = compose(flat.image, glyph: glyph, background: fill,
                                 cover: fullBleed ? shape : nil) else { return image }
        return NSImage(cgImage: tile, size: NSSize(width: size / 2, height: size / 2))
    }

    // MARK: - Analysis

    /// Bounding box of the visible pixels (rows from the top).
    private static func shapeBox(_ px: [UInt8]) -> Box? {
        var minX = size, minY = size, maxX = -1, maxY = -1
        for y in 0..<size {
            for x in 0..<size where px[(y * size + x) * 4 + 3] > 25 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return Box(left: minX, top: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Background color of the icon, if it has one: at least 3 of the 4 points halfway along the sides
    /// (just inside the shape) must be opaque and of the same color.
    private static func backgroundColor(_ px: [UInt8], shape: Box) -> RGB? {
        let ix = max(1, shape.width * 6 / 100), iy = max(1, shape.height * 6 / 100)
        let cx = shape.left + shape.width / 2, cy = shape.top + shape.height / 2
        let points = [(cx, shape.top + iy), (cx, shape.top + shape.height - 1 - iy),
                      (shape.left + ix, cy), (shape.left + shape.width - 1 - ix, cy)]
        let opaque: [RGB] = points.compactMap { (point) -> RGB? in
            let i = (point.1 * size + point.0) * 4
            return px[i + 3] > 230 ? color(px, at: i) : nil
        }
        guard opaque.count >= 3 else { return nil }
        let median: RGB = (opaque.map { $0.r }.sorted()[opaque.count / 2],
                           opaque.map { $0.g }.sorted()[opaque.count / 2],
                           opaque.map { $0.b }.sorted()[opaque.count / 2])
        let close = opaque.filter { distance($0, median) < 60 }
        guard close.count >= 3 else { return nil }
        return (close.map { $0.r }.reduce(0, +) / close.count,
                close.map { $0.g }.reduce(0, +) / close.count,
                close.map { $0.b }.reduce(0, +) / close.count)
    }

    /// true if the background reaches the corners of the shape (a square icon, not a circle
    /// or a rounded square): then the icon can cover the tile instead of being surrounded by a fill.
    private static func cornersOpaque(_ px: [UInt8], shape: Box) -> Bool {
        let left = shape.left + 1, right = shape.left + shape.width - 2
        let top = shape.top + 1, bottom = shape.top + shape.height - 2
        guard right > left, bottom > top else { return false }
        return [(left, top), (right, top), (left, bottom), (right, bottom)]
            .allSatisfy { px[($0.1 * size + $0.0) * 4 + 3] > 230 }
    }

    /// Bounding box of the symbol: opaque pixels whose color differs from the background.
    private static func glyphBox(_ px: [UInt8], background: RGB) -> Box? {
        var minX = size, minY = size, maxX = -1, maxY = -1
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                guard px[i + 3] > 128, distance(color(px, at: i), background) > 60 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return Box(left: minX, top: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Actual color of the pixel (the data is premultiplied by alpha).
    private static func color(_ px: [UInt8], at i: Int) -> RGB {
        let a = Int(px[i + 3])
        guard a > 0 else { return (0, 0, 0) }
        return (min(255, Int(px[i]) * 255 / a), min(255, Int(px[i + 1]) * 255 / a), min(255, Int(px[i + 2]) * 255 / a))
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        let dr = Double(a.r - b.r), dg = Double(a.g - b.g), db = Double(a.b - b.b)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    // MARK: - Drawing

    /// Draws the icon in a 128 px square (aspect ratio preserved), optionally on a solid background.
    /// In the data, row 0 is the top one.
    private static func rasterize(_ source: CGImage, background: RGB?) -> Raster? {
        guard let ctx = context() else { return nil }
        if let bg = background { fill(ctx, with: bg) }
        let w = CGFloat(source.width), h = CGFloat(source.height), n = CGFloat(size)
        let scale = n / max(w, h, 1)
        ctx.draw(source, in: CGRect(x: (n - w * scale) / 2, y: (n - h * scale) / 2,
                                    width: w * scale, height: h * scale))
        guard let data = ctx.data, let image = ctx.makeImage() else { return nil }
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                              count: size * size * 4))
        return Raster(bytes: bytes, image: image)
    }

    /// Final tile: solid background and the icon scaled so the symbol is centered and always the same size.
    /// With `cover` (the icon's own background box) the icon is scaled and placed so that box covers the
    /// whole tile: the fill never shows next to the icon's background.
    private static func compose(_ flat: CGImage, glyph: Box, background: RGB, cover: Box?) -> CGImage? {
        guard let ctx = context() else { return nil }
        fill(ctx, with: background)
        let n = CGFloat(size)
        var s = n * glyphFill / CGFloat(max(glyph.width, glyph.height))
        if let box = cover { s = max(s, n / CGFloat(min(box.width, box.height))) }
        let centerX = CGFloat(glyph.left) + CGFloat(glyph.width) / 2
        let centerYFromTop = CGFloat(glyph.top) + CGFloat(glyph.height) / 2
        // The context has its origin at the bottom: row r from the top sits at y = (n - r) from the image bottom.
        var originX = n / 2 - centerX * s
        var originY = n / 2 - (n - centerYFromTop) * s
        if let box = cover {
            // Keep the symbol centered as far as possible, without uncovering any edge of the tile.
            let left = CGFloat(box.left) * s, right = CGFloat(box.left + box.width) * s
            let bottom = (n - CGFloat(box.top + box.height)) * s, top = (n - CGFloat(box.top)) * s
            originX = min(max(originX, n - right), -left)
            originY = min(max(originY, n - top), -bottom)
        }
        ctx.draw(flat, in: CGRect(x: originX, y: originY, width: n * s, height: n * s))
        return ctx.makeImage()
    }

    private static func context() -> CGContext? {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .high
        return ctx
    }

    /// Fills with a color read from these same pixels: it is set in the context's own color space,
    /// so it is written back exactly as it was read (no conversion between color spaces).
    private static func fill(_ ctx: CGContext, with c: RGB) {
        let components: [CGFloat] = [CGFloat(c.r) / 255, CGFloat(c.g) / 255, CGFloat(c.b) / 255, 1]
        guard let color = CGColor(colorSpace: colorSpace, components: components) else { return }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
}
