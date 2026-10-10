import Cocoa
import WebKit

/// Gestisce la web view di un servizio: caricamento, link, popup di login, download,
/// upload di file, badge, notifiche e icona.
final class ServiceController: NSObject, WKNavigationDelegate, WKUIDelegate,
                               WKScriptMessageHandler, WKDownloadDelegate {
    var config: ServiceConfig          // nome e opzioni aggiornabili al volo da Impostazioni
    let webView: WKWebView
    weak var app: AppController?
    var tile: ServiceTile?
    private(set) var badgeCount = 0
    private var iconFetched = false
    private var wasOffHome = false
    private var popups: [PopupWindow] = []
    private var downloads: [ObjectIdentifier: URL] = [:]

    private static let webSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript"]

    init(config: ServiceConfig, app: AppController) {
        self.config = config
        self.app = app

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // login persistente tra un avvio e l'altro
        configuration.applicationNameForUserAgent = safariUserAgentSuffix()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: Scripts.notificationShim, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: false, in: .page))
        content.addUserScript(WKUserScript(source: Scripts.notificationBridge, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: false, in: .defaultClient))
        if let badgeScript = Scripts.badge(config.badge) {
            content.addUserScript(WKUserScript(source: badgeScript, injectionTime: .atDocumentEnd,
                                               forMainFrameOnly: true, in: .defaultClient))
        }
        configuration.userContentController = content

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        content.add(self, contentWorld: .defaultClient, name: "hubNotify")
        content.add(self, contentWorld: .defaultClient, name: "hubBadge")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true   // Safari > Sviluppo, utile per correggere i badge
        }
    }

    func start() {
        _ = webView.load(URLRequest(url: config.url))
    }

    func notificationClicked(_ jsId: String) {
        let safe = jsId.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        webView.evaluateJavaScript("window.__hubNotifyClick && window.__hubNotifyClick('\(safe)')",
                                   completionHandler: nil)
    }

    func popupClosed(_ popup: PopupWindow) {
        popups.removeAll { $0 === popup }
    }

    // MARK: - Messaggi dagli script

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "hubBadge":
            guard let body = message.body as? [String: Any] else { return }
            let count = (body["count"] as? NSNumber)?.intValue ?? 0
            let dot = (body["dot"] as? NSNumber)?.boolValue ?? false
            badgeCount = count
            tile?.badgeCount = count
            tile?.badgeDot = dot
            app?.badgesChanged()
        case "hubNotify":
            guard let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            handleNotification(object)
        default:
            break
        }
    }

    private func handleNotification(_ object: [String: Any]) {
        let action = object["action"] as? String ?? ""
        let jsId = object["id"] as? String ?? UUID().uuidString
        let tag = object["tag"] as? String ?? ""
        // Stesso tag = la nuova notifica sostituisce la precedente (come nel browser).
        let identifier = tag.isEmpty ? "\(config.id)|\(jsId)" : "\(config.id)|tag:\(tag)"

        if action == "close" {
            Notifier.shared.remove(identifier: identifier)
            return
        }
        guard action == "show" else { return }
        // Notifiche spente, in pausa, silenzio durante il focus, o lo stai già guardando
        guard app?.shouldNotify(from: self) ?? true else { return }
        let hide = app?.hideNotificationContent ?? false
        Notifier.shared.show(identifier: identifier, serviceId: config.id, serviceName: config.name,
                             jsId: jsId,
                             title: hide ? "" : (object["title"] as? String ?? ""),
                             body: hide ? "New notification" : (object["body"] as? String ?? ""),
                             silent: !config.sound || (object["silent"] as? Bool ?? false))
    }

    // MARK: - Navigazione

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()

        // mailto:, zoommtg:, slack:// ecc. → app di sistema, ma solo se l'hai cliccato tu
        // (evita che Slack apra da solo l'app desktop al login).
        if !Self.webSchemes.contains(scheme) {
            if navigationAction.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
            return
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, navigationAction.navigationType == .linkActivated, scheme == "http" || scheme == "https" {
            let otherSite = baseDomain(url.host) != baseDomain(config.url.host) && !isAuthHost(url.host)
            if navigationAction.modifierFlags.contains(.command) || otherSite {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(Self.responsePolicy(navigationResponse))
    }

    static func responsePolicy(_ navigationResponse: WKNavigationResponse) -> WKNavigationResponsePolicy {
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let onHome = webView.url?.host == config.url.host
        if !onHome {
            wasOffHome = true
        } else if wasOffHome {
            // Login appena riuscito in questa vista: fa entrare anche i servizi dello stesso account.
            wasOffHome = false
            app?.refreshSiblings(of: self)
        }
        fetchIconIfNeeded()
    }

    func reloadHome() {
        _ = webView.load(URLRequest(url: config.url))
    }

    /// Esce dal servizio: cancella cookie e dati dei suoi domini, poi ricarica.
    /// I servizi sullo stesso dominio (es. Gmail e Calendar) escono insieme.
    func resetData() {
        let base = baseDomain(config.url.host)
        var domains: Set<String> = [base]
        if ["office.com", "microsoft.com", "live.com", "outlook.com", "office365.com"].contains(base) {
            domains.formUnion(["microsoftonline.com", "live.com", "microsoft.com", "office.com"])
        }
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { [weak self] records in
            let matching = records.filter { domains.contains($0.displayName.lowercased()) }
            dataStore.removeData(ofTypes: types, for: matching) {
                self?.app?.reloadServices(withBaseDomain: base)
            }
        }
    }

    /// Chiude il servizio quando viene rimosso da Impostazioni (libera pagina e processi).
    func teardown() {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        _ = webView.load(URLRequest(url: URL(string: "about:blank")!))
        webView.removeFromSuperview()
        tile?.removeFromSuperview()
        popups.forEach { $0.window.close() }
        popups.removeAll()
    }

    /// Login completato in un popup e arrivato sulla pagina del servizio:
    /// la pagina si apre nella vista principale (i cookie sono condivisi, quindi sei già dentro).
    func finishLogin(at url: URL) {
        wasOffHome = false
        _ = webView.load(URLRequest(url: url))
        app?.refreshSiblings(of: self)
        app?.show(service: self)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        _ = webView.reload()
    }

    // MARK: - Icona del servizio

    private func fetchIconIfNeeded() {
        // Solo una volta per avvio e solo sulla pagina del servizio (non sulla pagina di login di Google).
        guard !iconFetched, webView.url?.host == config.url.host else { return }
        iconFetched = true
        webView.evaluateJavaScript(Scripts.faviconCandidates) { [weak self] result, _ in
            guard let self = self,
                  let json = result as? String,
                  let data = json.data(using: .utf8),
                  let list = (try? JSONSerialization.jsonObject(with: data)) as? [String] else { return }
            let id = self.config.id
            IconStore.fetchBest(from: list.compactMap { URL(string: $0) }) { [weak self] image, imageData in
                guard let image = image, let imageData = imageData else { return }
                IconStore.saveAuto(id: id, data: imageData)
                if IconStore.override(id: id) == nil { self?.tile?.image = image }
                self?.app?.iconsChanged()
            }
        }
    }

    // MARK: - Finestre, file, permessi

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let address = url?.absoluteString ?? ""
        let blank = address.isEmpty || address == "about:blank"
        if blank || isAuthHost(url?.host) {
            // Popup di login OAuth (o finestra vuota che verrà riempita via script)
            let popup = PopupWindow(configuration: configuration, owner: self, showImmediately: !blank)
            popups.append(popup)
            return popup.webView
        }
        if let url = url { NSWorkspace.shared.open(url) }   // tutti gli altri link: browser predefinito
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = config.name
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = config.name
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annulla")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    // Microfono/fotocamera (huddle Slack, note vocali WhatsApp). macOS chiede comunque il permesso la prima volta.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    // MARK: - Download (in ~/Downloads)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = Self.uniqueURL(in: folder, filename: suggestedFilename)
        downloads[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Fa rimbalzare lo stack Download nel Dock, come Safari
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.DownloadFileFinished"),
                                                     object: url.path)
        Notifier.shared.show(identifier: "download|\(url.path)", serviceId: config.id, serviceName: config.name,
                             jsId: nil, title: "Download completato", body: url.lastPathComponent, silent: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }

    static func uniqueURL(in folder: URL, filename: String) -> URL {
        let name = filename.isEmpty ? "download" : filename
        var url = folder.appendingPathComponent(name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)")
            i += 1
        }
        return url
    }
}

/// Finestra secondaria per i popup di login (es. "Accedi con Google" su Claude o ChatGPT).
/// Se un popup vuoto finisce su un sito esterno, il link va al browser e il popup si chiude.
final class PopupWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let window: NSWindow
    let webView: WKWebView
    weak var owner: ServiceController?
    private var trusted: Bool
    private var authSeen: Bool      // il popup è passato da una pagina di login
    private var handingOff = false
    private var closing = false

    init(configuration: WKWebViewConfiguration, owner: ServiceController, showImmediately: Bool) {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 700)
        webView = WKWebView(frame: frame, configuration: configuration)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        self.owner = owner
        self.trusted = showImmediately
        self.authSeen = showImmediately
        super.init()
        window.isReleasedWhenClosed = false
        window.title = owner.config.name
        window.contentView = webView
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if showImmediately { show() }
    }

    private func show() {
        guard !window.isVisible else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        guard !closing else { return }
        closing = true
        webView.stopLoading()
        window.close()
        owner?.popupClosed(self)
    }

    func windowWillClose(_ notification: Notification) {
        if !closing {
            closing = true
            owner?.popupClosed(self)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            decisionHandler(.allow)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame && isAuthHost(url.host) { authSeen = true }
        // Login finito: la pagina del servizio non va mostrata nel popup.
        if isMainFrame && authSeen && url.host == owner?.config.url.host { window.orderOut(nil) }
        if isMainFrame && !trusted {
            if isAuthHost(url.host) || baseDomain(url.host) == baseDomain(owner?.config.url.host) {
                trusted = true
                show()
            } else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                close()
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(ServiceController.responsePolicy(navigationResponse))
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = owner
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = owner
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // Il popup OAuth "classico" si chiude da solo con window.close() a login completato.
    func webViewDidClose(_ webView: WKWebView) {
        close()
    }

    // Login finito su una pagina del servizio (es. "Accedi" di Gmail → mail.google.com):
    // la pagina passa nella vista principale e il popup si chiude.
    // La breve attesa lascia chiudersi da soli i popup OAuth che rispondono alla pagina principale.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard authSeen, !handingOff, let url = webView.url, url.host == owner?.config.url.host else { return }
        handingOff = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, !self.closing else { return }
            self.owner?.finishLogin(at: url)
            self.close()
        }
    }
}
