import Cocoa

/// App colors, in dark and light versions (Settings > Appearance).
/// Views read them on every draw: after a theme change, redrawing is enough (see refresh).
enum Theme {
    static private(set) var isLight = false

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    private static func pick(_ dark: NSColor, _ light: NSColor) -> NSColor { isLight ? light : dark }
    private static func ink(_ alpha: CGFloat) -> NSColor {   // white on the dark theme, midnight blue on the light one
        pick(rgb(1, 1, 1, alpha), rgb(0.106, 0.137, 0.200, alpha))
    }

    static var sidebar: NSColor      { pick(rgb(0.039, 0.067, 0.125), rgb(0.914, 0.929, 0.953)) } // frame
    static var tile: NSColor         { pick(rgb(0.125, 0.129, 0.141), rgb(0.863, 0.882, 0.914)) }
    static var tileHover: NSColor    { pick(rgb(0.165, 0.169, 0.180), rgb(0.824, 0.847, 0.882)) }
    static var tileSelected: NSColor { pick(rgb(0.180, 0.184, 0.196), rgb(0.973, 0.976, 0.984)) }
    static var accent: NSColor       { rgb(0.898, 0.440, 0.227) }                                 // active indicator
    static var badge: NSColor        { rgb(1.000, 0.231, 0.188) }
    static var content: NSColor      { pick(rgb(0.039, 0.067, 0.125), rgb(1, 1, 1)) }             // card background
    static var todoAccent: NSColor   { pick(rgb(0.184, 0.608, 0.914), rgb(0.102, 0.498, 0.816)) } // panel blue
    static var railActive: NSColor   { pick(rgb(0.145, 0.192, 0.267), rgb(0.831, 0.894, 0.965)) }
    static var breakGreen: NSColor   { pick(rgb(0.247, 0.792, 0.557), rgb(0.071, 0.576, 0.373)) } // Focus break
    static var railIcon: NSColor     { ink(0.55) }
    static var railIconHover: NSColor { ink(0.85) }
    static var hoverFill: NSColor    { ink(0.06) }
    static var separator: NSColor    { ink(isLight ? 0.16 : 0.14) }
    static var progressTrack: NSColor { ink(isLight ? 0.10 : 0.08) }
    static var tileLetter: NSColor   { ink(isLight ? 0.75 : 0.85) }
    static var tileRing: NSColor     { ink(isLight ? 0.22 : 0.28) }

    /// Applies the chosen theme ("Automatic" follows macOS). Returns true if it changed.
    @discardableResult
    static func apply(_ mode: AppearanceMode) -> Bool {
        let light: Bool
        switch mode {
        case .dark: light = false
        case .light: light = true
        case .system: light = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
        guard light != isLight else { return false }
        isLight = light
        return true
    }

    /// Redraws a view and the views it contains, after a theme change.
    static func refresh(_ view: NSView) {
        view.needsDisplay = true
        (view as? RailButton)?.updateTint()
        view.subviews.forEach(refresh)
    }
}

/// A sidebar icon: rounded tile, service icon, red badge.
final class ServiceTile: NSView {
    static let side: CGFloat = 52   // tile side length
    static let pad: CGFloat = 7     // margin for the overhanging badge and the glow

    /// Original service icon; it is normalized into a full tile (see IconStyle).
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
                                       options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Pointing hand on hover: shows that it is clickable.
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func draw(_ dirtyRect: NSRect) {
        let tileRect = NSRect(x: Self.pad, y: Self.pad, width: Self.side, height: Self.side)
        let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 14, yRadius: 14)

        // Tile (with glow when selected)
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

        // Icon or initial
        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        if let rendered = rendered {
            NSGraphicsContext.current?.imageInterpolation = .high
            rendered.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: nil)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: Theme.tileLetter,
            ]
            let str = letter as NSString
            let s = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: tileRect.midX - s.width / 2, y: tileRect.midY - s.height / 2),
                     withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()

        // On hover: thin ring (the tile background is now covered by the icon)
        if hovering && !isSelected {
            Theme.tileRing.setStroke()
            let ring = NSBezierPath(roundedRect: tileRect.insetBy(dx: -2.5, dy: -2.5), xRadius: 16.5, yRadius: 16.5)
            ring.lineWidth = 1.5
            ring.stroke()
        }

        // Badge: a number, or a dot for "unread without mentions"
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
        Theme.sidebar.setFill()   // ring that separates the badge from the tile
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

/// Vertical column with the icons and the active-service indicator on the left edge.
final class SidebarView: NSView {
    static let width: CGFloat = 80
    private(set) var tiles: [ServiceTile] = []
    private var footerButton: RailButton?   // at the bottom: Settings

    // The icons scroll when they don't all fit vertically; the gear stays fixed at the bottom.
    private let scrollView = NSScrollView()
    private let tileList = SidebarTileList()
    private var separatorsAfter: Set<Int> = []
    private var revealPending = false   // after the next layout, scroll to the selected icon

    var selectedIndex = 0 {
        didSet {
            for (i, tile) in tiles.enumerated() { tile.isSelected = (i == selectedIndex) }
            tileList.selected = tiles.indices.contains(selectedIndex) ? tiles[selectedIndex] : nil
            revealPending = true
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false   // scroll with the trackpad or mouse wheel
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = tileList
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var isFlipped: Bool { true }

    /// separatorsAfter: indexes of the tiles with a separator line below them.
    func setTiles(_ newTiles: [ServiceTile], separatorsAfter: Set<Int> = []) {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = newTiles
        self.separatorsAfter = separatorsAfter
        tiles.forEach { tileList.addSubview($0) }
        tileList.selected = tiles.indices.contains(selectedIndex) ? tiles[selectedIndex] : nil
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
        var listBottom = bounds.height
        if let footer = footerButton {
            let s = RailButton.size
            footer.frame = NSRect(x: (bounds.width - s) / 2, y: bounds.height - s - 14, width: s, height: s)
            listBottom = footer.frame.minY - 6
        }
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, listBottom))
        let size = ServiceTile.side + ServiceTile.pad * 2
        var y: CGFloat = 6
        var separators: [CGFloat] = []
        for (index, tile) in tiles.enumerated() {
            tile.frame = NSRect(x: (bounds.width - size) / 2, y: y, width: size, height: size)
            y += size + 4
            // No line after the last icon: it would separate nothing.
            if separatorsAfter.contains(index) && index < tiles.count - 1 {
                separators.append(y + 3)
                y += 10
            }
        }
        tileList.separators = separators
        tileList.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(y + 2, scrollView.frame.height))
        tileList.needsDisplay = true
        if revealPending, tiles.indices.contains(selectedIndex) {
            revealPending = false
            let tile = tiles[selectedIndex]
            _ = tile.scrollToVisible(tile.bounds)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

/// Scrollable sidebar content: the icons and the active-service indicator, which scrolls with them.
private final class SidebarTileList: NSView {
    weak var selected: NSView? { didSet { needsDisplay = true } }
    var separators: [CGFloat] = [] { didSet { needsDisplay = true } }   // y of each separator line

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.separator.setFill()
        for y in separators {
            NSBezierPath(roundedRect: NSRect(x: bounds.midX - 18, y: y - 1, width: 36, height: 2),
                         xRadius: 1, yRadius: 1).fill()
        }
        guard let f = selected?.frame else { return }
        Theme.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: -3, y: f.midY - 18, width: 6, height: 36),
                     xRadius: 3, yRadius: 3).fill()
    }
}
