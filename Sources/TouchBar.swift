import Cocoa
import WebKit

/// Touch Bar of the main window: one icon per service, tap it to switch (like ⌘1…⌘9).
/// The focused view decides what the Touch Bar shows, and in WorkHub that is almost always a web view:
/// the window's web views are HubWebViews, which show this Touch Bar instead of WebKit's own.
final class ServicesTouchBar: NSObject, NSTouchBarDelegate {
    static let shared = ServicesTouchBar()
    static let changed = Notification.Name("WorkHubServicesTouchBarChanged")
    private static let itemID = NSTouchBarItem.Identifier("local.workhub.services")
    private static let iconSide: CGFloat = 22

    /// Called with the index of the tapped service.
    var onSelect: ((Int) -> Void)?
    private var icons: [NSImage] = []
    private var names: [String] = []
    private var selected = 0
    private let controls = NSHashTable<NSSegmentedControl>.weakObjects()   // one per Touch Bar shown

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.itemID]
        bar.principalItemIdentifier = Self.itemID   // centered
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.itemID, !icons.isEmpty else { return nil }
        let control = NSSegmentedControl(images: icons, trackingMode: .selectOne,
                                         target: self, action: #selector(tapped(_:)))
        for (index, name) in names.enumerated() { control.setToolTip(name, forSegment: index) }
        control.selectedSegment = selected
        controls.add(control)
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = control
        item.customizationLabel = "Services"
        return item
    }

    @objc private func tapped(_ sender: NSSegmentedControl) {
        onSelect?(sender.selectedSegment)
    }

    /// New list of services (added, removed, reordered, new icons): every Touch Bar is rebuilt.
    func setServices(_ services: [(icon: NSImage?, name: String)], selected: Int) {
        icons = services.map { Self.icon($0.icon, name: $0.name) }
        names = services.map { $0.name }
        self.selected = selected
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// The selected service changed: the highlighted icon follows it.
    func select(_ index: Int) {
        selected = index
        for control in controls.allObjects where index < control.segmentCount { control.selectedSegment = index }
    }

    /// The service's tile as in the sidebar (rounded, same normalized icon), or its initial on a gray tile.
    private static func icon(_ image: NSImage?, name: String) -> NSImage {
        let tile = image.map(IconStyle.normalize)
        let letter = String(name.prefix(1)).uppercased() as NSString
        return NSImage(size: NSSize(width: iconSide, height: iconSide), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).addClip()
            if let tile = tile {
                tile.draw(in: rect)
            } else {
                NSColor(white: 0.32, alpha: 1).setFill()
                rect.fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                            .foregroundColor: NSColor.white]
                let size = letter.size(withAttributes: attrs)
                letter.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
            }
            return true
        }
    }
}

/// Web view of the main window (services, Todos, Focus): shows the services Touch Bar.
/// WebKit's own Touch Bar (word suggestions while typing) is not shown in these views.
final class HubWebView: WKWebView {
    private var observer: NSObjectProtocol?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        observer = NotificationCenter.default.addObserver(forName: ServicesTouchBar.changed, object: nil,
                                                          queue: .main) { [weak self] _ in
            self?.touchBar = nil   // rebuilt with the new services the next time it's shown
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func makeTouchBar() -> NSTouchBar? {
        ServicesTouchBar.shared.makeTouchBar()
    }
}
