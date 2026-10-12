import Cocoa

/// Service icons.
/// - Manual override: ~/Library/Application Support/WorkHub/icons/<id>.png (always wins).
/// - Automatic: downloaded from the service's page after login and saved in icons/auto/<id>.
enum IconStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WorkHub/icons", isDirectory: true)
    }

    static func override(id: String) -> NSImage? {
        NSImage(contentsOf: directory.appendingPathComponent("\(id).png"))
    }

    static func load(id: String) -> NSImage? {
        if let image = override(id: id) { return image }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("auto/\(id)")) else { return nil }
        return NSImage(data: data)
    }

    /// Icon chosen in Settings: saved as PNG and used instead of the favicon.
    static func setOverride(id: String, from url: URL) {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? png.write(to: directory.appendingPathComponent("\(id).png"), options: .atomic)
    }

    static func removeOverride(id: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).png"))
    }

    static func pngDataURL(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    static func saveAuto(id: String, data: Data) {
        let dir = directory.appendingPathComponent("auto", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(id))
    }

    /// Downloads the candidates in order and keeps the image with the most pixels (stops at ≥120px).
    static func fetchBest(from urls: [URL], completion: @escaping (NSImage?, Data?) -> Void) {
        var best: (image: NSImage, data: Data, pixels: Int)?
        func next(_ i: Int) {
            if i >= urls.count || (best?.pixels ?? 0) >= 120 {
                let result = best
                DispatchQueue.main.async { completion(result?.image, result?.data) }
                return
            }
            URLSession.shared.dataTask(with: urls[i]) { data, response, _ in
                if let data = data,
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let image = NSImage(data: data) {
                    let pixels = image.representations.map { $0.pixelsWide }.max() ?? 0
                    if pixels > (best?.pixels ?? 0) { best = (image, data, pixels) }
                }
                next(i + 1)
            }.resume()
        }
        next(0)
    }
}
