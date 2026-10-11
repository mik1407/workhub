import Cocoa
import WebKit

final class AppController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let sidebar = SidebarView()
    let content = NSView()
    let rail = RightRail()
    let panelContainer = NSView()
    static let cardRadius: CGFloat = 10   // angoli arrotondati di servizio e pannello
    static let cardGap: CGFloat = 8       // margine sotto le card e spazio tra servizio e pannello
    let todoPanel = TodoPanel()
    let todoButton = RailButton(image: RailIcons.doubleCheck(), tooltip: "Todos  ⌘T")
    let focusTimer = FocusTimer()
    let focusPanel = LocalPanel(page: "focus", handler: "focus")
    let focusButton = RailButton(image: RailIcons.stopwatch(), tooltip: "Focus  ⌘⇧F")
    var contentTrailing: NSLayoutConstraint!   // 0 = servizio a tutta larghezza, -360 = lascia posto al pannello
    var panelLeading: NSLayoutConstraint!      // -360 = pannello visibile, 0 = nascosto sotto la barra destra
    var todoMenuItem: NSMenuItem?
    var focusMenuItem: NSMenuItem?
    var openPanel: SidePanel?                  // pannello aperto a destra (uno alla volta)
    var panelTransition = 0                    // invalida le animazioni superate da un nuovo click

    enum SidePanel: String { case todos, focus }
    private(set) var services: [ServiceController] = []
    private(set) var selectedIndex = 0
    private var keyMonitor: Any?
    let store = SettingsStore.shared
    var settingsWindow: SettingsWindow?
    var goMenu: NSMenu?
    var reminderWork: DispatchWorkItem?
    var overdueTimer: Timer?
    private var appearanceObserver: NSKeyValueObservation?

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
        // Tema "Automatic": segue il passaggio di macOS da chiaro a scuro e viceversa.
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applyTheme() }
        }
    }

    /// Tema chiaro o scuro (Impostazioni > Appearance) su cornice, barre, pannelli e Impostazioni.
    /// I servizi non cambiano: seguono il tema di macOS, come in Safari.
    func applyTheme() {
        guard Theme.apply(store.settings.appearance) else { return }
        window.backgroundColor = Theme.sidebar
        for card in [content, panelContainer] { card.layer?.backgroundColor = Theme.content.cgColor }
        Theme.refresh(sidebar)
        Theme.refresh(rail)
        todoPanel.panel.applyTheme()
        focusPanel.applyTheme()
        settingsWindow?.applyTheme()
        focusChanged()   // colore dell'anello del Focus
    }

    // MARK: - Setup

    private func setupWindow() {
        window.title = "WorkHub"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true   // la barra del titolo prende il colore della sidebar
        window.backgroundColor = Theme.sidebar
        window.isReleasedWhenClosed = false        // ⌘W nasconde, i servizi restano attivi
        window.minSize = NSSize(width: 900, height: 500)
        window.delegate = self
        window.center()
        _ = window.setFrameAutosaveName("WorkHubMainWindow")

        let root = NSView()
        window.contentView = root
        // Servizio e pannello Todos sono "card" con angoli arrotondati sulla cornice blu notte.
        for card in [content, panelContainer] {
            card.wantsLayer = true
            card.layer?.cornerRadius = Self.cardRadius
            card.layer?.cornerCurve = .continuous
            card.layer?.masksToBounds = true
            card.layer?.backgroundColor = Theme.content.cgColor
        }
        for page in [todoPanel.webView, focusPanel.webView] {
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

        // Ordine di sovrapposizione: servizio < pannello < barra destra
        for view in [sidebar, content, panelContainer, rail] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        // sidebar | servizio | barra destra. Il pannello scorre sopra il servizio,
        // così aprendo e chiudendo non si vede mai spazio vuoto.
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
        rail.add(todoButton)
        rail.add(focusButton)
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

    /// ⌘1…⌘9 intercettati prima della pagina web (alcuni servizi usano gli stessi tasti),
    /// per codice tasto fisico: funzionano con qualsiasi layout di tastiera.
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
        services.forEach { $0.start() }   // tutti caricati subito: badge e notifiche anche in background
        let savedPanel = UserDefaults.standard.string(forKey: "openPanel").flatMap(SidePanel.init(rawValue:))
            ?? (UserDefaults.standard.bool(forKey: "todosOpen") ? .todos : nil)
        setPanel(savedPanel, animated: false, focus: false)
        let savedId = UserDefaults.standard.string(forKey: "selectedService")
        let legacyIndex = UserDefaults.standard.integer(forKey: "selectedIndex")
        let index = savedId.flatMap { id in services.firstIndex { $0.config.id == id } }
            ?? (services.indices.contains(legacyIndex) ? legacyIndex : 0)
        select(index)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Servizi (da Impostazioni)

    /// Allinea servizi, tessere della sidebar e menu Vai alla configurazione:
    /// aggiunte, rimozioni, nuovo ordine, nomi e opzioni. Se cambiano URL o badge il servizio si ricarica.
    func applyServices(_ configs: [ServiceConfig], isLaunch: Bool) {
        let selectedId = current?.config.id
        var next: [ServiceController] = []
        for config in configs {
            if let existing = services.first(where: { $0.config.id == config.id }) {
                if existing.config.url == config.url && existing.config.badge == config.badge {
                    existing.config = config
                    next.append(existing)
                    continue
                }
                existing.teardown()
            }
            let service = makeService(config)
            if !isLaunch { service.start() }
            next.append(service)
        }
        for old in services where !next.contains(where: { $0 === old }) { old.teardown() }
        services = next
        for (index, service) in services.enumerated() {
            service.tile?.letter = String(service.config.name.prefix(1))
            service.tile?.toolTip = index < 9 ? "\(service.config.name)  ⌘\(index + 1)" : service.config.name
            service.tile?.needsDisplay = true
        }
        sidebar.setTiles(services.compactMap { $0.tile })
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
        service.tile = tile
        return service
    }

    /// Dopo "Esci e azzera dati": ricarica tutti i servizi dello stesso dominio.
    func reloadServices(withBaseDomain domain: String) {
        for service in services where baseDomain(service.config.url.host) == domain { service.reloadHome() }
    }

    func iconsChanged() {
        if settingsWindow?.isVisible == true { pushSettings() }
    }

    // MARK: - Regole delle notifiche

    /// true se la notifica di quel servizio va mostrata adesso.
    func shouldNotify(from service: ServiceController) -> Bool {
        guard service.config.notify else { return false }
        let rules = store.settings.notifications
        if rules.isPaused { return false }
        if rules.silenceDuringFocus && focusTimer.phase == .focus && !focusTimer.isPaused
            && !service.config.allowDuringFocus { return false }
        return !isUserLooking(at: service)
    }

    var hideNotificationContent: Bool { store.settings.notifications.hideContent }

    // MARK: - Stato

    func select(_ index: Int) {
        guard services.indices.contains(index) else { return }
        selectedIndex = index
        for (i, service) in services.enumerated() { service.webView.isHidden = (i != index) }
        sidebar.selectedIndex = index
        _ = window.makeFirstResponder(services[index].webView)
        UserDefaults.standard.set(services[index].config.id, forKey: "selectedService")
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

    /// Dopo un login ricarica i servizi dello stesso account rimasti fuori
    /// (es. login in Gmail → entra anche Calendar, senza rifare l'accesso).
    func refreshSiblings(of service: ServiceController) {
        let domain = baseDomain(service.config.url.host)
        for other in services where other !== service
            && baseDomain(other.config.url.host) == domain
            && other.webView.url?.host != other.config.url.host {
            other.reloadHome()
        }
    }

    func badgesChanged() {
        let total = services.filter { $0.config.countInDock }.reduce(0) { $0 + $1.badgeCount }
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
    }

    /// true se l'utente sta guardando proprio quel servizio: in quel caso niente notifica.
    func isUserLooking(at service: ServiceController) -> Bool {
        NSApp.isActive && window.isKeyWindow && !window.isMiniaturized && current === service
    }
}
