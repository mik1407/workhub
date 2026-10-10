import Cocoa

enum Theme {
    static let sidebar      = NSColor(srgbRed: 0.039, green: 0.067, blue: 0.125, alpha: 1) // blu notte
    static let tile         = NSColor(srgbRed: 0.125, green: 0.129, blue: 0.141, alpha: 1)
    static let tileHover    = NSColor(srgbRed: 0.165, green: 0.169, blue: 0.180, alpha: 1)
    static let tileSelected = NSColor(srgbRed: 0.180, green: 0.184, blue: 0.196, alpha: 1)
    static let accent       = NSColor(srgbRed: 0.898, green: 0.440, blue: 0.227, alpha: 1) // indicatore attivo
    static let badge        = NSColor(srgbRed: 1.000, green: 0.231, blue: 0.188, alpha: 1)
    static let content      = NSColor(srgbRed: 0.039, green: 0.067, blue: 0.125, alpha: 1) // come la cornice
    static let todoAccent   = NSColor(srgbRed: 0.184, green: 0.608, blue: 0.914, alpha: 1) // blu del pannello Todos
    static let railActive   = NSColor(srgbRed: 0.145, green: 0.192, blue: 0.267, alpha: 1)
    static let breakGreen   = NSColor(srgbRed: 0.247, green: 0.792, blue: 0.557, alpha: 1) // pausa del Focus
}

/// Un'icona della sidebar: riquadro arrotondato, icona del servizio, badge rosso.
final class ServiceTile: NSView {
    static let side: CGFloat = 52   // lato del riquadro
    static let pad: CGFloat = 7     // margine per il badge che sborda e per il bagliore

    /// Icona originale del servizio; viene normalizzata in una tessera piena (vedi IconStyle).
    var image: NSImage? {
        didSet {
            rendered = image.map(IconStyle.normalize)
            needsDisplay = true
        }
    }
    private var rendered: NSImage?
    var letter = "?"
    var isSelected = false { didSet { needsDisplay = true } }
    var badgeCount = 0 { didSet { if oldValue != badgeCount { needsDisplay = true } } }
    var badgeDot = false { didSet { if oldValue != badgeDot { needsDisplay = true } } }
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let tileRect = NSRect(x: Self.pad, y: Self.pad, width: Self.side, height: Self.side)
        let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 14, yRadius: 14)

        // Riquadro (con bagliore se selezionato)
        NSGraphicsContext.saveGraphicsState()
        if isSelected {
            let glow = NSShadow()
            glow.shadowColor = Theme.accent.withAlphaComponent(0.45)
            glow.shadowBlurRadius = 9
            glow.shadowOffset = .zero
            glow.set()
        }
        (isSelected ? Theme.tileSelected : (hovering ? Theme.tileHover : Theme.tile)).setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Icona o iniziale
        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        if let rendered = rendered {
            NSGraphicsContext.current?.imageInterpolation = .high
            rendered.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: nil)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            let str = letter as NSString
            let s = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: tileRect.midX - s.width / 2, y: tileRect.midY - s.height / 2),
                     withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Al passaggio del mouse: anello sottile (lo sfondo della tessera ora è coperto dall'icona)
        if hovering && !isSelected {
            NSColor.white.withAlphaComponent(0.28).setStroke()
            let ring = NSBezierPath(roundedRect: tileRect.insetBy(dx: -2.5, dy: -2.5), xRadius: 16.5, yRadius: 16.5)
            ring.lineWidth = 1.5
            ring.stroke()
        }

        // Badge: numero, oppure pallino per "non letti senza menzioni"
        guard badgeCount > 0 || badgeDot else { return }
        let text: String? = badgeCount > 0 ? (badgeCount > 99 ? "99+" : String(badgeCount)) : nil
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.map { ($0 as NSString).size(withAttributes: attrs) } ?? .zero
        let h: CGFloat = 20
        let w = max(h, textSize.width + 10)
        let r = NSRect(x: tileRect.maxX - w + 5, y: tileRect.minY - 5, width: w, height: h)
        Theme.sidebar.setFill()   // anello che stacca il badge dal riquadro
        NSBezierPath(roundedRect: r.insetBy(dx: -2, dy: -2), xRadius: h / 2 + 2, yRadius: h / 2 + 2).fill()
        Theme.badge.setFill()
        NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2).fill()
        if let text = text {
            (text as NSString).draw(at: NSPoint(x: r.midX - textSize.width / 2, y: r.midY - textSize.height / 2),
                                    withAttributes: attrs)
        } else {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: r.midX - 3, y: r.midY - 3, width: 6, height: 6)).fill()
        }
    }
}

/// Colonna verticale con le icone e l'indicatore del servizio attivo sul bordo sinistro.
final class SidebarView: NSView {
    static let width: CGFloat = 80
    private(set) var tiles: [ServiceTile] = []
    private var footerButton: RailButton?   // in fondo: Impostazioni

    var selectedIndex = 0 {
        didSet {
            for (i, tile) in tiles.enumerated() { tile.isSelected = (i == selectedIndex) }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    func setTiles(_ newTiles: [ServiceTile]) {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = newTiles
        tiles.forEach { addSubview($0) }
        needsLayout = true
    }

    func setFooterButton(_ button: RailButton) {
        footerButton?.removeFromSuperview()
        footerButton = button
        addSubview(button)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if let footer = footerButton {
            let s = RailButton.size
            footer.frame = NSRect(x: (bounds.width - s) / 2, y: bounds.height - s - 14, width: s, height: s)
        }
        let size = ServiceTile.side + ServiceTile.pad * 2
        var y: CGFloat = 6
        for tile in tiles {
            tile.frame = NSRect(x: (bounds.width - size) / 2, y: y, width: size, height: size)
            y += size + 4
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        NSBezierPath(rect: bounds).fill()
        guard tiles.indices.contains(selectedIndex) else { return }
        let f = tiles[selectedIndex].frame
        Theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: -3, y: f.midY - 18, width: 6, height: 36),
                     xRadius: 3, yRadius: 3).fill()
    }
}
