import Cocoa
import Network
import WebKit

final class AppController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let sidebar = SidebarView()
    let content = NSView()
    let rail = RightRail()
    let panelContainer = NSView()
    static let cardRadius: CGFloat = 10   // rounded corners of service and panel
    static let cardGap: CGFloat = 8       // margin below the cards and gap between service and panel
    let todoPanel = TodoPanel()
    let todoButton = RailButton(image: RailIcons.doubleCheck(), tooltip: "Todos  ⌘T")
    let focusTimer = FocusTimer()
    let focusPanel = LocalPanel(page: "focus", handler: "focus", servicesTouchBar: true)
    let focusButton = RailButton(image: RailIcons.stopwatch(), tooltip: "Focus  ⌘⇧F")
    let snippetsPanel = SnippetsPanel()
    let snippetsButton = RailButton(image: RailIcons.clipboard(), tooltip: "Snippets")
    var snippetsMenuItem: NSMenuItem?
    var contentTrailing: NSLayoutConstraint!   // 0 = full-width service, -360 = leaves room for the panel
    var panelLeading: NSLayoutConstraint!      // -360 = panel visible, 0 = hidden under the right rail
    var todoMenuItem: NSMenuItem?
    var focusMenuItem: NSMenuItem?
    var openPanel: SidePanel?                  // panel open on the right (one at a time)
    var panelTransition = 0                    // invalidates animations superseded by a new click

    enum SidePanel: String { case todos, focus, snippets }
    private(set) var services: [ServiceController] = []
    private(set) var selectedIndex = 0
    private var keyMonitor: Any?
    let store = SettingsStore.shared
    var settingsWindow: SettingsWindow?
    var goMenu: NSMenu?
    var reminderWork: DispatchWorkItem?
    var overdueTimer: Timer?
    private var appearanceObserver: NSKeyValueObservation?
    private let network = NWPathMonitor()

    var current: ServiceController? {
        services.indices.contains(selectedIndex) ? services[selectedIndex] : nil
    }

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        setupWindow()
        setupServices()
        setupShortcuts()
        setupTodos()
        ServicesTouchBar.shared.onSelect = { [weak self] index in self?.select(index) }
        // "Automatic" theme: follows macOS switching from light to dark and back.
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyTheme() }
        }
    }

    /// Light or dark theme (Settings > Appearance) for the frame, bars, panels and Settings.
    /// Services don't change: they follow the macOS theme, as in Safari.
    func applyTheme() {
        guard Theme.apply(store.settings.appearance) else { return }
        window.backgroundColor = Theme.sidebar
        for card in [content, panelContainer] { card.layer?.backgroundColor = Theme.content.cgColor }
        Theme.refresh(sidebar)
        Theme.refresh(rail)
        todoPanel.panel.applyTheme()
        focusPanel.applyTheme()
        snippetsPanel.panel.applyTheme()
        settingsWindow?.applyTheme()
        focusChanged()   // Focus button ring color
    }

    // MARK: - Setup

    private func setupWindow() {
        window.title = "WorkHub"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true   // the title bar takes the sidebar color
        window.backgroundColor = Theme.sidebar
        window.isReleasedWhenClosed = false        // ⌘W hides, services keep running
        window.minSize = NSSize(width: 900, height: 500)
        window.delegate = self
        window.center()
        _ = window.setFrameAutosaveName("WorkHubMainWindow")

        let root = NSView()
        window.contentView = root
        // Service and Todos panel are "cards" with rounded corners on the midnight-blue frame.
        for card in [content, panelContainer] {
            card.wantsLayer = true
            card.layer?.cornerRadius = Self.cardRadius
            card.layer?.cornerCurve = .continuous
            card.layer?.masksToBounds = true
            card.layer?.backgroundColor = Theme.content.cgColor
        }
        for page in [todoPanel.webView, focusPanel.webView, snippetsPanel.webView] {
            page.translatesAutoresizingMaskIntoConstraints = false
            page.isHidden = true
            panelContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: panelContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
                page.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: panelContainer.trailingAnchor),
            ])
        }

        // Stacking order: service < panel < right rail
        for view in [sidebar, content, panelContainer, rail] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        // sidebar | service | right rail. The panel slides over the service,
        // so opening and closing never shows empty space.
        contentTrailing = content.trailingAnchor.constraint(equalTo: rail.leadingAnchor)
        panelLeading = panelContainer.leadingAnchor.constraint(equalTo: rail.leadingAnchor)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SidebarView.width),

            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.cardGap),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentTrailing,

            panelContainer.topAnchor.constraint(equalTo: root.topAnchor),
            panelContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.cardGap),
            panelLeading,
            panelContainer.widthAnchor.constraint(equalToConstant: LocalPanel.width),

            rail.topAnchor.constraint(equalTo: root.topAnchor),
            rail.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            rail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rail.widthAnchor.constraint(equalToConstant: RightRail.width),
        ])
        panelContainer.isHidden = true

        let settingsButton = RailButton(image: RailIcons.gear(), tooltip: "Settings  ⌘,")
        settingsButton.onClick = { [weak self] in self?.openSettings(nil) }
        sidebar.setFooterButton(settingsButton)

        todoButton.onClick = { [weak self] in self?.toggleTodos(nil) }
        focusButton.onClick = { [weak self] in self?.toggleFocus(nil) }
        snippetsButton.onClick = { [weak self] in self?.toggleSnippets(nil) }
        rail.add(todoButton)
        rail.add(focusButton)
        rail.add(snippetsButton)
        setupFocus()
    }

    private func setupServices() {
        applyServices(store.settings.services, isLaunch: true)
        focusTimer.apply(store.settings.focus)

        Notifier.shared.onClick = { [weak self] serviceId, jsId in
            if serviceId == "todos" {
                self?.showWindow()
                self?.setPanel(.todos, animated: true, focus: false)
                if let id = jsId { self?.todoPanel.reveal(id) }
                return
            }
            if serviceId == "focus" {
                self?.showWindow()
                self?.setPanel(.focus, animated: true, focus: false)
                return
            }
            guard let self = self,
                  let index = self.services.firstIndex(where: { $0.config.id == serviceId }) else { return }
            self.showWindow()
            self.select(index)
            if let jsId = jsId { self.services[index].notificationClicked(jsId) }
        }
    }

    /// ⌘1…⌘9 intercepted before the web page (some services use the same keys),
    /// by physical key code: they work with any keyboard layout.
    private func setupShortcuts() {
        let numberKeys: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            if mods == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.toggleFocus(nil)
                return nil
            }
            guard mods == .command else { return event }
            if event.charactersIgnoringModifiers?.lowercased() == "t" {
                self.toggleTodos(nil)
                return nil
            }
            guard let index = numberKeys[event.keyCode],
                  self.services.indices.contains(index) else { return event }
            self.showWindow()
            self.select(index)
            return nil
        }
    }

    func start() {
        services.forEach { $0.start() }   // all loaded right away: badges and notifications in the background too
        let savedPanel = UserDefaults.standard.string(forKey: "openPanel").flatMap(SidePanel.init(rawValue:))
            ?? (UserDefaults.standard.bool(forKey: "todosOpen") ? .todos : nil)
        setPanel(savedPanel, animated: false, focus: false)
        let savedId = UserDefaults.standard.string(forKey: "selectedService")
        let legacyIndex = UserDefaults.standard.integer(forKey: "selectedIndex")
        let index = savedId.flatMap { id in services.firstIndex { $0.config.id == id } }
            ?? (services.indices.contains(legacyIndex) ? legacyIndex : 0)
        select(index)
        window.makeKeyAndOrderFront(nil)
        // Network back (e.g. Wi-Fi connecting after login): services that never loaded try again.
        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { self?.services.forEach { $0.retryIfNeverLoaded() } }
        }
        network.start(queue: .global(qos: .utility))
    }

    // MARK: - Services (from Settings)

    /// Syncs services, sidebar tiles and the Go menu with the configuration:
    /// additions, removals, new order, names and options. If the URL or badge changes, the service reloads.
    func applyServices(_ configs: [ServiceConfig], isLaunch: Bool) {
        let selectedId = current?.config.id
        var next: [ServiceController] = []
        for config in configs {
            if let existing = services.first(where: { $0.config.id == config.id }) {
                if existing.config.url == config.url && existing.config.badge == config.badge
                    && existing.config.separateSession == config.separateSession {
                    existing.config = config
                    next.append(existing)
                    continue
                }
                // Separate sign-in turned off: its own storage is no longer needed.
                existing.teardown(deleteData: existing.config.separateSession && !config.separateSession)
            }
            let service = makeService(config)
            if !isLaunch { service.start() }
            next.append(service)
        }
        for old in services where !next.contains(where: { $0 === old }) { old.teardown(deleteData: true) }
        services = next
        for (index, service) in services.enumerated() {
            service.tile?.letter = String(service.config.name.prefix(1))
            service.tile?.toolTip = index < 9 ? "\(service.config.name)  ⌘\(index + 1)" : service.config.name
            service.tile?.needsDisplay = true
        }
        refreshTouchBar()
        sidebar.setTiles(services.compactMap { $0.tile },
                         separatorsAfter: Set(services.indices.filter { services[$0].config.separatorAfter }))
        rebuildGoMenu()
        if !isLaunch {
            let index = selectedId.flatMap { id in services.firstIndex { $0.config.id == id } } ?? 0
            select(index)
        }
        badgesChanged()
    }

    private func makeService(_ config: ServiceConfig) -> ServiceController {
        let service = ServiceController(config: config, app: self)
        let web = service.webView
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isHidden = true
        content.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.topAnchor.constraint(equalTo: content.topAnchor),
            web.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        let tile = ServiceTile()
        tile.letter = String(config.name.prefix(1))
        tile.image = IconStore.load(id: config.id)
        tile.onClick = { [weak self, weak service] in
            guard let self = self, let service = service,
                  let index = self.services.firstIndex(where: { $0 === service }) else { return }
            self.select(index)
        }
        tile.onReload = { [weak service] in service?.reload() }
        service.tile = tile
        return service
    }

    /// After "Sign out and reset data": reloads all services on the same domain.
    func reloadServices(withBaseDomain domain: String) {
        for service in services where !service.ownSession && baseDomain(service.config.url.host) == domain {
            service.reloadHome()
        }
    }

    func iconsChanged() {
        refreshTouchBar()
        if settingsWindow?.isVisible == true { pushSettings() }
    }

    /// Services, icons or order changed: the Touch Bar shows the new list.
    func refreshTouchBar() {
        ServicesTouchBar.shared.setServices(services.map { (icon: $0.tile?.image, name: $0.config.name) },
                                            selected: selectedIndex)
        window.touchBar = nil   // the window's own Touch Bar (when no web view has the focus) is rebuilt too
    }

    // When no web view has the focus, the window itself shows the services Touch Bar.
    func windowDidBecomeKey(_ notification: Notification) {
        if window.touchBar == nil { window.touchBar = ServicesTouchBar.shared.makeTouchBar() }
    }

    // MARK: - Notification rules

    /// true if that service's notification should be shown now.
    func shouldNotify(from service: ServiceController) -> Bool {
        guard service.config.notify else { return false }
        let rules = store.settings.notifications
        if rules.isPaused { return false }
        if rules.silenceDuringFocus && focusTimer.phase == .focus && !focusTimer.isPaused
            && !service.config.allowDuringFocus { return false }
        return !isUserLooking(at: service)
    }

    var hideNotificationContent: Bool { store.settings.notifications.hideContent }

    // MARK: - State

    func select(_ index: Int) {
        guard services.indices.contains(index) else { return }
        selectedIndex = index
        for (i, service) in services.enumerated() { service.webView.isHidden = (i != index) }
        // The selected page goes on top of the stack: macOS hands a file dragged from the Finder to the topmost
        // page of the stack even when it's hidden, so only the last service received drops.
        // sortSubviews reorders without removing the views, so their constraints stay.
        content.sortSubviews({ a, b, context in
            let selected = Unmanaged<NSView>.fromOpaque(context!).takeUnretainedValue()
            if a === selected { return .orderedDescending }
            if b === selected { return .orderedAscending }
            return .orderedSame
        }, context: Unmanaged.passUnretained(services[index].webView).toOpaque())
        sidebar.selectedIndex = index
        _ = window.makeFirstResponder(services[index].webView)
        UserDefaults.standard.set(services[index].config.id, forKey: "selectedService")
        services[index].retryIfNeverLoaded()
        ServicesTouchBar.shared.select(index)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func show(service: ServiceController) {
        guard let index = services.firstIndex(where: { $0 === service }) else { return }
        showWindow()
        select(index)
    }

    /// After a sign-in, reloads the services of the same account left signed out
    /// (e.g. signing in to Gmail → Calendar signs in too, without logging in again).
    func refreshSiblings(of service: ServiceController) {
        guard !service.ownSession else { return }   // a separate sign-in is its own account
        let domain = baseDomain(service.config.url.host)
        for other in services where other !== service && !other.ownSession
            && baseDomain(other.config.url.host) == domain
            && other.webView.url?.host != other.config.url.host {
            other.reloadHome()
        }
    }

    func badgesChanged() {
        let total = services.filter { $0.config.countInDock }.reduce(0) { $0 + $1.badgeCount }
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
    }

    /// true if the user is looking at that very service: in that case, no notification.
    func isUserLooking(at service: ServiceController) -> Bool {
        NSApp.isActive && window.isKeyWindow && !window.isMiniaturized && current === service
    }
}
