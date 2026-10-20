import Cocoa
import WebKit

/// Touch Bar of the main window: one icon per service, tap it to switch (like ⌘1…⌘9).
/// The focused view decides what the Touch Bar shows, and in WorkHub that is almost always a web view:
/// the window's web views are HubWebViews, which show this Touch Bar instead of WebKit's own.
final class ServicesTouchBar: NSObject, NSTouchBarDelegate {
    static let shared = ServicesTouchBar()
    static let changed = Notification.Name("WorkHubServicesTouchBarChanged")
    private static let itemID = NSTouchBarItem.Identifier("local.workhub.services")
    private static let iconSide: CGFloat = 22   // icon inside the key
    private static let keyWidth: CGFloat = 60   // about the width of the F1…F12 keys

    /// Called with the index of the tapped service.
    var onSelect: ((Int) -> Void)?
    private var icons: [NSImage] = []
    private var names: [String] = []
    private var selected = 0
    private let rows = NSHashTable<NSStackView>.weakObjects()   // one row of buttons per Touch Bar shown

    func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.itemID]
        bar.principalItemIdentifier = Self.itemID   // centered
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.itemID, !icons.isEmpty else { return nil }
        // Standard Touch Bar keys (the same rounded gray keys as F1…F12), with the icon in the middle.
        let buttons: [NSButton] = icons.enumerated().map { index, icon in
            let button = NSButton(image: icon, target: self, action: #selector(tapped(_:)))
            button.imageScaling = .scaleNone
            button.tag = index
            button.setAccessibilityLabel(names[index])
            button.widthAnchor.constraint(equalToConstant: Self.keyWidth).isActive = true
            return button
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 6
        rows.add(row)
        highlight(row)
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = row
        item.customizationLabel = "Services"
        return item
    }

    @objc private func tapped(_ sender: NSButton) {
        onSelect?(sender.tag)
    }

    /// The selected service's key is blue, like an active key in macOS's own Touch Bar.
    private func highlight(_ row: NSStackView) {
        for case let button as NSButton in row.arrangedSubviews {
            button.bezelColor = button.tag == selected ? NSColor.controlAccentColor : nil
        }
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
        rows.allObjects.forEach(highlight)
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
    private var dragTypes: [NSPasteboard.PasteboardType] = []   // the file types WebKit accepts when dropped

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        dragTypes = registeredDraggedTypes
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

    // MARK: - Drops only on the visible page
    // The services (and the side panels) are stacked in the same window and only one is visible, but macOS
    // hands a file dragged from the Finder to the topmost page that accepts drops, even a hidden one: a file
    // dropped on ChatGPT ended up in WhatsApp (the last service), or in a closed panel that ignores it.
    // A hidden page (itself or inside a hidden panel) stops accepting drops until it's shown again.

    override func viewDidHide() {
        super.viewDidHide()
        updateDropRegistration()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateDropRegistration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDropRegistration()
    }

    private func updateDropRegistration() {
        if dragTypes.isEmpty { dragTypes = registeredDraggedTypes }
        if isHiddenOrHasHiddenAncestor {
            unregisterDraggedTypes()
        } else if !dragTypes.isEmpty {
            registerForDraggedTypes(dragTypes)
        }
    }

    // MARK: - Drag and drop diagnostics
    // Files dragged from the Finder sometimes don't reach the page: these log what WebKit receives and
    // answers (log show --predicate 'eventMessage CONTAINS "WorkHub drag"'). Behavior is unchanged.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(sender)
        log("entered", sender, "operation \(operation.rawValue)")
        return operation
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = super.performDragOperation(sender)
        log("dropped", sender, accepted ? "accepted" : "refused")
        return accepted
    }

    private func log(_ event: String, _ info: NSDraggingInfo, _ result: String) {
        let files = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                        options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let page = url?.host ?? "no page"
        let active = NSApp.isActive ? "app active" : "app inactive"
        let key = window?.isKeyWindow == true ? "key window" : "not key"
        let types = info.draggingPasteboard.types?.map(\.rawValue).joined(separator: ",") ?? "-"
        let line = "\(Date()) \(event) on \(page): \(files.count) file(s), types \(types), \(active), \(key), \(result)"
        NSLog("WorkHub drag %@", line)
        Self.appendToDragLog(line)
    }

    /// Also in ~/Library/Application Support/WorkHub/drag-log.txt (last ~200 lines), readable without Console.
    private static func appendToDragLog(_ line: String) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub/drag-log.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = (old.split(separator: "\n").suffix(199).map(String.init) + [line]).joined(separator: "\n") + "\n"
        try? lines.write(to: url, atomically: true, encoding: .utf8)
    }
}
