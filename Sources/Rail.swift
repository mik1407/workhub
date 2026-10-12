import Cocoa

/// Round button of the right rail (SF Symbol icon, active state in blue).
final class RailButton: NSView {
    static let size: CGFloat = 44

    var isActive = false { didSet { needsDisplay = true; updateTint() } }
    /// Progress ring around the button (0…1); nil = no ring.
    var progress: CGFloat? { didSet { if oldValue != progress { needsDisplay = true } } }
    var progressColor: NSColor = Theme.todoAccent { didSet { needsDisplay = true } }
    var progressDimmed = false { didSet { if oldValue != progressDimmed { needsDisplay = true } } }
    /// Red number at the top right (0 = hidden).
    var badgeCount = 0 { didSet { if oldValue != badgeCount { needsDisplay = true } } }
    var onClick: (() -> Void)?
    private let imageView = NSImageView()
    private var hovering = false { didSet { needsDisplay = true; updateTint() } }

    /// Hand-drawn icon (template image: takes the button's color).
    init(image: NSImage, tooltip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = tooltip
        updateTint()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var isFlipped: Bool { true }

    // All clicks on the button (even over the icon) land here.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

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

    func updateTint() {
        imageView.contentTintColor = isActive ? Theme.todoAccent
            : (hovering ? Theme.railIconHover : Theme.railIcon)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isActive || hovering {
            (isActive ? Theme.railActive : Theme.hoverFill).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)).fill()
        }
        drawProgress()
        drawBadge()
    }

    private func drawBadge() {
        guard badgeCount > 0 else { return }
        let text = badgeCount > 9 ? "9+" : String(badgeCount)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let h: CGFloat = 16
        let w = max(h, size.width + 8)
        let r = NSRect(x: bounds.maxX - w - 1, y: 1, width: w, height: h)
        Theme.sidebar.setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: -2, dy: -2), xRadius: h / 2 + 2, yRadius: h / 2 + 2).fill()
        Theme.badge.setFill()
        NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2).fill()
        (text as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
    }

    private func drawProgress() {
        guard let progress = progress else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2 - 2.5
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2
        Theme.progressTrack.setStroke()
        track.stroke()
        // Flipped view: increasing angles = clockwise, -90° = top.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: -90,
                      endAngle: -90 + 360 * min(max(progress, 0.001), 1), clockwise: false)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        progressColor.withAlphaComponent(progressDimmed ? 0.4 : 1).setStroke()
        arc.stroke()
    }
}

/// Vector icons for the right rail.
enum RailIcons {
    /// Double check mark for the Todos panel.
    static func doubleCheck(size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width / 24            // drawn on a 24×24 grid
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            let path = NSBezierPath()
            path.lineWidth = 2 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: p(2, 12.5)); path.line(to: p(7, 17.5)); path.line(to: p(18, 6.5))     // first check
            path.move(to: p(13, 16)); path.line(to: p(14.5, 17.5)); path.line(to: p(22, 10))    // second check
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Todos"
        return image
    }
}

extension RailIcons {
    /// Settings gear (system symbol).
    static func gear() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        return NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 20, height: 20))
    }

    /// Stopwatch for the Focus panel.
    static func stopwatch(size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            let path = NSBezierPath(ovalIn: NSRect(x: 4.5 * s, y: 6 * s, width: 15 * s, height: 15 * s))
            path.move(to: p(9.5, 2.5)); path.line(to: p(14.5, 2.5))     // button
            path.move(to: p(12, 2.5)); path.line(to: p(12, 6))          // stem
            path.move(to: p(12, 13.5)); path.line(to: p(12, 9.5))       // hand
            path.move(to: p(18.2, 6.6)); path.line(to: p(19.6, 5.2))    // side notch
            path.lineWidth = 2 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Focus"
        return image
    }
}

/// Vertical bar on the right side of the window.
final class RightRail: NSView {
    static let width: CGFloat = 56
    private var buttons: [RailButton] = []

    override var isFlipped: Bool { true }

    func add(_ button: RailButton) {
        buttons.append(button)
        addSubview(button)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 10
        for button in buttons {
            button.frame = NSRect(x: (bounds.width - RailButton.size) / 2, y: y,
                                  width: RailButton.size, height: RailButton.size)
            y += RailButton.size + 6
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.sidebar.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}
