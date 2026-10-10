import Cocoa
import WebKit
import ServiceManagement
import UniformTypeIdentifiers

final class AppController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let sidebar = SidebarView()
    private let content = NSView()
    private let rail = RightRail()
    private let panelContainer = NSView()
    private static let cardRadius: CGFloat = 10   // angoli arrotondati di servizio e pannello
    private static let cardGap: CGFloat = 8       // margine sotto le card e spazio tra servizio e pannello
    private let todoPanel = TodoPanel()
    private let todoButton = RailButton(image: RailIcons.doubleCheck(), tooltip: "Todos  ⌘T")
    private let focusTimer = FocusTimer()
    private let focusPanel = LocalPanel(page: "focus", handler: "focus")
    private let focusButton = RailButton(image: RailIcons.stopwatch(), tooltip: "Focus  ⌘⇧F")
    private var contentTrailing: NSLayoutConstraint!   // 0 = servizio a tutta larghezza, -360 = lascia posto al pannello
    private var panelLeading: NSLayoutConstraint!      // -360 = pannello visibile, 0 = nascosto sotto la barra destra
    private var todoMenuItem: NSMenuItem?
    private var focusMenuItem: NSMenuItem?
    private var openPanel: SidePanel?                  // pannello aperto a destra (uno alla volta)
    private var panelTransition = 0                    // invalida le animazioni superate da un nuovo click

    enum SidePanel: String { case todos, focus }
    private(set) var services: [ServiceController] = []
    private(set) var selectedIndex = 0
    private var keyMonitor: Any?
    private let store = SettingsStore()
    private var settingsWindow: SettingsWindow?
    private var goMenu: NSMenu?
    private var reminderWork: DispatchWorkItem?
    private var overdueTimer: Timer?

    private var current: ServiceController? {
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

    // MARK: - Todo: scadenze e promemoria

    private func setupTodos() {
        todoPanel.onSaved = { [weak self] json in self?.todosChanged(json) }
        todosChanged(todoPanel.lastState)
        // Un todo diventa scaduto col passare del tempo: badge ricontrollato ogni 30 secondi
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshOverdueBadge() }
        RunLoop.main.add(timer, forMode: .common)
        overdueTimer = timer
        // Pulsanti della notifica di scadenza
        Notifier.shared.onAction = { [weak self] action, service, id in
            guard service == "todos", let id = id, let self = self else { return }
            switch action {
            case "todo.done": self.todoPanel.apply("done", to: id)
            case "todo.snooze": self.todoPanel.apply("snooze", to: id)
            default: break
            }
        }
    }

    private func todosChanged(_ json: String) {
        refreshOverdueBadge()
        // Riprogramma i promemoria poco dopo l'ultima modifica (non a ogni tasto)
        reminderWork?.cancel()
        let work = DispatchWorkItem { TodoReminders.reschedule(from: json) }
        reminderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func refreshOverdueBadge() {
        let count = TodoReminders.overdueCount(in: todoPanel.lastState)
        todoButton.badgeCount = count
        todoButton.toolTip = count > 0 ? "Todos  ⌘T (\(count) overdue)" : "Todos  ⌘T"
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
    private func applyServices(_ configs: [ServiceConfig], isLaunch: Bool) {
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

    // MARK: - Impostazioni

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let settings = SettingsWindow()
            settings.onLoad = { [weak self] in self?.pushSettings() }
            settings.onMessage = { [weak self] message in self?.handleSettingsMessage(message) }
            settingsWindow = settings
        }
        settingsWindow?.show()
        pushSettings()
    }

    private func handleSettingsMessage(_ message: [String: Any]) {
        let id = message["id"] as? String
        switch message["action"] as? String {
        case "save"?:
            guard let json = message["settings"] as? String, let data = json.data(using: .utf8),
                  let incoming = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
            applySettings(incoming)
            if store.settings != incoming { pushSettings() }   // valori corretti: la pagina si riallinea
        case "resetData"?:
            if let id = id { services.first(where: { $0.config.id == id })?.resetData() }
        case "changeIcon"?:
            if let id = id { chooseIcon(for: id) }
        case "resetIcon"?:
            if let id = id {
                IconStore.removeOverride(id: id)
                refreshTile(id)
                pushSettings()
            }
        default:
            break
        }
    }

    private func applySettings(_ incoming: AppSettings) {
        let previous = store.settings
        store.update(incoming)
        let now = store.settings
        if now.services != previous.services { applyServices(now.services, isLaunch: false) }
        if now.focus != previous.focus { focusTimer.apply(now.focus) }
        badgesChanged()
    }

    private func chooseIcon(for id: String) {
        guard let settingsWindow = settingsWindow else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an icon (square images work best)"
        panel.beginSheetModal(for: settingsWindow.window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            IconStore.setOverride(id: id, from: url)
            self.refreshTile(id)
            self.pushSettings()
        }
    }

    private func refreshTile(_ id: String) {
        services.first(where: { $0.config.id == id })?.tile?.image = IconStore.load(id: id)
    }

    /// Stato per la pagina Impostazioni: impostazioni, catalogo, icone attuali.
    private func pushSettings() {
        guard let settingsWindow = settingsWindow else { return }
        var icons: [String: String] = [:]
        for service in store.settings.services {
            if let image = IconStore.load(id: service.id), let url = IconStore.pngDataURL(IconStyle.normalize(image)) {
                icons[service.id] = url
            }
        }
        let extra: [String: Any] = [
            "catalog": serviceCatalog.map { ["id": $0.id, "name": $0.name, "url": $0.url.absoluteString, "badge": $0.badge.rawValue] },
            "icons": icons,
            "customIcons": store.settings.services.filter { IconStore.override(id: $0.id) != nil }.map { $0.id },
            "now": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: extra),
              let extraJSON = String(data: data, encoding: .utf8) else { return }
        settingsWindow.push("{\"settings\":\(store.json),\"extra\":\(extraJSON)}")
    }

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

    // MARK: - Pannelli a destra (Todos, Focus)

    @objc func toggleTodos(_ sender: Any?) {
        showWindow()
        setPanel(openPanel == .todos ? nil : .todos, animated: true, focus: true)
    }

    @objc func toggleFocus(_ sender: Any?) {
        showWindow()
        setPanel(openPanel == .focus ? nil : .focus, animated: true, focus: true)
    }

    /// Apre un pannello (o lo cambia se ne è già aperto un altro) oppure chiude con nil.
    private func setPanel(_ target: SidePanel?, animated: Bool, focus: Bool) {
        openPanel = target
        todoButton.isActive = target == .todos
        focusButton.isActive = target == .focus
        todoMenuItem?.state = target == .todos ? .on : .off
        focusMenuItem?.state = target == .focus ? .on : .off
        UserDefaults.standard.set(target?.rawValue ?? "", forKey: "openPanel")
        if let target = target {
            // Cambia contenuto; in chiusura resta visibile quello attuale mentre scorre via.
            todoPanel.webView.isHidden = target != .todos
            focusPanel.webView.isHidden = target != .focus
            if target == .focus { focusPanel.run("window.focusUpdate && window.focusUpdate(\(focusTimer.stateJSON))") }
        }
        panelTransition += 1
        let token = panelTransition
        let panel = panelContainer
        let width = LocalPanel.width
        let contentInset = width + Self.cardGap

        if !animated {
            panel.isHidden = target == nil
            panelLeading.constant = target == nil ? 0 : -width
            contentTrailing.constant = target == nil ? 0 : -contentInset
            return
        }

        if let target = target {
            // 1. il pannello entra scorrendo sopra il servizio (se è già aperto, cambia solo contenuto)
            // 2. poi il servizio si restringe dietro il pannello (il ridisegno resta coperto)
            panel.isHidden = false
            slidePanel(to: -width) { [weak self] in
                guard let self = self, self.panelTransition == token else { return }
                self.contentTrailing.constant = -contentInset
            }
            if focus {
                switch target {
                case .todos:
                    _ = window.makeFirstResponder(todoPanel.webView)
                    todoPanel.focusInput()
                case .focus:
                    _ = window.makeFirstResponder(focusPanel.webView)
                }
            }
        } else {
            // 1. il servizio si allarga dietro il pannello
            // 2. quando la pagina ha ridisegnato alla nuova larghezza, il pannello esce scorrendo
            contentTrailing.constant = 0
            window.contentView?.layoutSubtreeIfNeeded()
            afterRepaint(of: current?.webView) { [weak self] in
                guard let self = self, self.panelTransition == token else { return }
                self.slidePanel(to: 0) { [weak self] in
                    guard let self = self, self.panelTransition == token else { return }
                    panel.isHidden = true
                }
            }
            if focus, let web = current?.webView { _ = window.makeFirstResponder(web) }
        }
    }

    // MARK: - Focus (Pomodoro)

    private func setupFocus() {
        focusPanel.onMessage = { [weak self] body in
            guard let self = self else { return }
            switch (body as? [String: Any])?["action"] as? String {
            case "addSounds"?: self.addSounds()
            case "showSounds"?: NSWorkspace.shared.open(SoundLibrary.folder)
            default: self.focusTimer.handle(body)
            }
        }
        focusPanel.onLoad = { [weak self] in self?.focusChanged() }
        focusTimer.onChange = { [weak self] in self?.focusChanged() }
        focusTimer.onPhaseChange = { [weak self] phase in
            guard let self = self else { return }
            let settings = self.focusTimer.settings
            let title: String
            switch phase {
            case .longRest: title = "Long break: \(settings.longBreakMinutes) minutes"
            case .rest: title = "Break: \(settings.breakMinutes) minutes"
            default: title = "Focus: \(settings.focusMinutes) minutes"
            }
            let body: String
            if self.focusTimer.waiting {
                body = phase.isBreak ? "Session done. Start the break when you're ready." : "Break over. Start focus when you're ready."
            } else {
                body = phase.isBreak ? "Step away from the screen." : "Pick one thing and work on it."
            }
            if settings.chime { _ = NSSound(named: "Glass")?.play() }   // con il suono di fine fase la notifica resta muta
            Notifier.shared.show(identifier: "focus-phase", serviceId: "focus", serviceName: "Focus", jsId: nil,
                                 title: title, body: body, silent: settings.chime)
        }
    }

    /// Aggiunge suoni scelti dal Finder alla cartella dei suoni e seleziona il primo.
    private func addSounds() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose sounds to use during focus"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self = self else { return }
            let added = SoundLibrary.add(panel.urls)
            self.focusTimer.reloadSounds()
            if let first = added.first { self.focusTimer.selectSound(first) }
        }
    }

    /// Aggiorna anello e tooltip del pulsante Focus e lo stato mostrato nel pannello.
    private func focusChanged() {
        let timer = focusTimer
        if timer.phase == .idle {
            focusButton.progress = nil
            focusButton.toolTip = "Focus  ⌘⇧F"
        } else {
            let left = Int(timer.remaining.rounded(.up))
            let label = timer.phase == .focus ? "Focus" : (timer.phase == .longRest ? "Long break" : "Break")
            focusButton.progress = CGFloat(1 - timer.remaining / max(timer.duration, 1))
            focusButton.progressColor = timer.phase == .focus ? Theme.todoAccent : Theme.breakGreen
            focusButton.progressDimmed = timer.isPaused
            focusButton.toolTip = timer.waiting
                ? "\(label) ready: click to start"
                : String(format: "%@ %ld:%02ld%@", label, left / 60, left % 60, timer.isPaused ? " (paused)" : "")
        }
        focusPanel.run("window.focusUpdate && window.focusUpdate(\(timer.stateJSON))")
    }

    private func slidePanel(to constant: CGFloat, completion: @escaping () -> Void) {
        guard let root = window.contentView else { completion(); return }
        root.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.panelLeading.constant = constant
            root.layoutSubtreeIfNeeded()
        }, completionHandler: completion)
    }

    /// Esegue `action` quando la pagina ha disegnato almeno due frame alla nuova dimensione
    /// (con un limite di sicurezza di 0,4 s se la pagina non risponde).
    private func afterRepaint(of webView: WKWebView?, _ action: @escaping () -> Void) {
        var done = false
        let finish = {
            if done { return }
            done = true
            action()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: finish)
        guard let webView = webView else { finish(); return }
        webView.callAsyncJavaScript(
            "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));",
            arguments: [:], in: nil, in: .defaultClient) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finish)
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

    // MARK: - Menu

    func buildMenu() {
        let main = NSMenu()
        let appName = "WorkHub"

        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "Informazioni su \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Impostazioni…", action: #selector(openSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        if #available(macOS 13.0, *) {
            let login = appMenu.addItem(withTitle: "Apri all'avvio del Mac",
                                        action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            appMenu.addItem(.separator())
        }
        appMenu.addItem(withTitle: "Nascondi \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Nascondi altre",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Mostra tutte",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Esci da \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        // Necessario per copia/incolla dentro le pagine web
        let edit = NSMenu(title: "Modifica")
        edit.addItem(withTitle: "Annulla", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Ripeti", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: main)

        let view = NSMenu(title: "Vista")
        view.addItem(withTitle: "Ricarica", action: #selector(reloadCurrent(_:)), keyEquivalent: "r").target = self
        let reloadAllItem = view.addItem(withTitle: "Ricarica tutti i servizi",
                                         action: #selector(reloadAllServices(_:)), keyEquivalent: "r")
        reloadAllItem.keyEquivalentModifierMask = [.command, .shift]
        reloadAllItem.target = self
        let homeItem = view.addItem(withTitle: "Pagina iniziale del servizio",
                                    action: #selector(goHome(_:)), keyEquivalent: "h")
        homeItem.keyEquivalentModifierMask = [.command, .shift]
        homeItem.target = self
        view.addItem(.separator())
        let todosItem = view.addItem(withTitle: "Pannello Todos", action: #selector(toggleTodos(_:)),
                                     keyEquivalent: "t")
        todosItem.target = self
        todosItem.state = openPanel == .todos ? .on : .off
        todoMenuItem = todosItem
        let focusItem = view.addItem(withTitle: "Focus", action: #selector(toggleFocus(_:)), keyEquivalent: "f")
        focusItem.keyEquivalentModifierMask = [.command, .shift]
        focusItem.target = self
        focusItem.state = openPanel == .focus ? .on : .off
        focusMenuItem = focusItem
        view.addItem(.separator())
        view.addItem(withTitle: "Indietro", action: #selector(navigateBack(_:)), keyEquivalent: "[").target = self
        view.addItem(withTitle: "Avanti", action: #selector(navigateForward(_:)), keyEquivalent: "]").target = self
        addSubmenu(view, to: main)

        let go = NSMenu(title: "Vai")
        goMenu = go
        rebuildGoMenu()
        addSubmenu(go, to: main)

        let windowMenu = NSMenu(title: "Finestra")
        windowMenu.addItem(withTitle: "Riduci a icona", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Chiudi", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(windowMenu, to: main)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    private func rebuildGoMenu() {
        guard let go = goMenu else { return }
        go.removeAllItems()
        for (index, service) in services.enumerated() {
            let item = go.addItem(withTitle: service.config.name, action: #selector(selectFromMenu(_:)),
                                  keyEquivalent: index < 9 ? String(index + 1) : "")
            item.tag = index
            item.target = self
        }
    }

    private func addSubmenu(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    /// Elemento di login gestito da macOS (Impostazioni di Sistema > Generali > Elementi login).
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Non riesco a cambiare l'apertura all'avvio"
            alert.informativeText = "\(error.localizedDescription)\n\nPuoi farlo da Impostazioni di Sistema > Generali > Elementi login."
            _ = alert.runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        sender.state = service.status == .enabled ? .on : .off
    }

    @objc private func selectFromMenu(_ sender: NSMenuItem) {
        showWindow()
        select(sender.tag)
    }

    @objc private func reloadCurrent(_ sender: Any?) { _ = current?.webView.reload() }
    @objc private func reloadAllServices(_ sender: Any?) { services.forEach { _ = $0.webView.reload() } }
    @objc private func goHome(_ sender: Any?) { current?.reloadHome() }
    @objc private func navigateBack(_ sender: Any?) { _ = current?.webView.goBack() }
    @objc private func navigateForward(_ sender: Any?) { _ = current?.webView.goForward() }
}
