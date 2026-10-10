import Cocoa

/// Rende omogenee le icone dei servizi nella sidebar.
/// Le favicon arrivano in forme diverse: alcune hanno uno sfondo pieno (quadrato o cerchio colorato),
/// altre sono solo il simbolo su trasparente. Qui diventano tutte tessere piene della stessa forma:
/// - icona con sfondo: lo sfondo si estende fino ai bordi della tessera;
/// - solo simbolo: tessera bianca.
/// In entrambi i casi il simbolo occupa sempre la stessa porzione della tessera.
enum IconStyle {
    private static let size = 128                // lato in pixel di analisi e risultato
    private static let glyphFill: CGFloat = 0.58 // lato maggiore del simbolo / lato della tessera

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

        // 1. Icona appiattita sul proprio sfondo: niente aloni sui bordi quando viene ingrandita.
        guard let flat = rasterize(source, background: fill),
              let tile = compose(flat.image, glyph: glyph, background: fill) else { return image }
        return NSImage(cgImage: tile, size: NSSize(width: size / 2, height: size / 2))
    }

    // MARK: - Analisi

    /// Riquadro dei pixel visibili (righe dall'alto).
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

    /// Colore di sfondo dell'icona, se ne ha uno: almeno 3 dei 4 punti a metà dei lati
    /// (appena all'interno della forma) devono essere opachi e dello stesso colore.
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

    /// Riquadro del simbolo: pixel opachi di colore diverso dallo sfondo.
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

    /// Colore reale del pixel (i dati sono premoltiplicati per l'alfa).
    private static func color(_ px: [UInt8], at i: Int) -> RGB {
        let a = Int(px[i + 3])
        guard a > 0 else { return (0, 0, 0) }
        return (min(255, Int(px[i]) * 255 / a), min(255, Int(px[i + 1]) * 255 / a), min(255, Int(px[i + 2]) * 255 / a))
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        let dr = Double(a.r - b.r), dg = Double(a.g - b.g), db = Double(a.b - b.b)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    // MARK: - Disegno

    /// Disegna l'icona in un quadrato di 128 px (proporzioni mantenute), opzionalmente su uno sfondo pieno.
    /// Nei dati, la riga 0 è quella in alto.
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

    /// Tessera finale: sfondo pieno e icona scalata con il simbolo centrato e sempre della stessa grandezza.
    private static func compose(_ flat: CGImage, glyph: Box, background: RGB) -> CGImage? {
        guard let ctx = context() else { return nil }
        fill(ctx, with: background)
        let n = CGFloat(size)
        let s = n * glyphFill / CGFloat(max(glyph.width, glyph.height))
        let centerX = CGFloat(glyph.left) + CGFloat(glyph.width) / 2
        let centerYFromTop = CGFloat(glyph.top) + CGFloat(glyph.height) / 2
        // Il contesto ha l'origine in basso: la riga r dall'alto sta a y = (n - r) dal fondo dell'immagine.
        let originX = n / 2 - centerX * s
        let originY = n / 2 - (n - centerYFromTop) * s
        ctx.draw(flat, in: CGRect(x: originX, y: originY, width: n * s, height: n * s))
        return ctx.makeImage()
    }

    private static func context() -> CGContext? {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .high
        return ctx
    }

    private static func fill(_ ctx: CGContext, with c: RGB) {
        ctx.setFillColor(CGColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
}
