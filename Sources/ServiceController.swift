import Cocoa
import WebKit

/// Manages a service's web view: loading, links, login popups, downloads,
/// file uploads, badge, notifications and icon.
final class ServiceController: NSObject, WKNavigationDelegate, WKUIDelegate,
                               WKScriptMessageHandler, WKDownloadDelegate {
    var config: ServiceConfig          // name and options, updatable on the fly from Settings
    let webView: WKWebView
    weak var app: AppController?
    var tile: ServiceTile?
    private(set) var badgeCount = 0
    private var iconFetched = false
    private var wasOffHome = false
    private var hasLoaded = false          // the page finished loading at least once in this session
    private var retryWork: DispatchWorkItem?
    private var retryCount = 0
    private var popups: [PopupWindow] = []
    private var downloads: [ObjectIdentifier: URL] = [:]

    private static let webSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript"]

    init(config: ServiceConfig, app: AppController) {
        self.config = config
        self.app = app

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // login persists across launches
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
            webView.isInspectable = true   // Safari > Develop, useful for fixing badges
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

    // MARK: - Messages from scripts

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
            // Only from the service (including its iframes, e.g. the chat inside Gmail): an iframe from another site
            // (ads, embedded content) cannot send notifications on behalf of the service.
            guard baseDomain(message.frameInfo.securityOrigin.host) == baseDomain(config.url.host),
                  let json = message.body as? String,
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
        // Same tag = the new notification replaces the previous one (as in the browser).
        let identifier = tag.isEmpty ? "\(config.id)|\(jsId)" : "\(config.id)|tag:\(tag)"

        if action == "close" {
            Notifier.shared.remove(identifier: identifier)
            return
        }
        guard action == "show" else { return }
        // Notifications off, paused, silenced during focus, or you're already looking at it
        guard app?.shouldNotify(from: self) ?? true else { return }
        let hide = app?.hideNotificationContent ?? false
        Notifier.shared.show(identifier: identifier, serviceId: config.id, serviceName: config.name,
                             jsId: jsId,
                             title: hide ? "" : (object["title"] as? String ?? ""),
                             body: hide ? "New notification" : (object["body"] as? String ?? ""),
                             silent: !config.sound || (object["silent"] as? Bool ?? false))
    }

    // MARK: - Navigation

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

        // mailto:, zoommtg:, slack:// etc. → system app, but only if you clicked it yourself
        // (stops Slack from opening the desktop app on its own at login).
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
            // Login just succeeded in this view: signs in the services on the same account too.
            wasOffHome = false
            app?.refreshSiblings(of: self)
        }
        hasLoaded = true
        retryWork?.cancel()
        retryCount = 0
        fetchIconIfNeeded()
    }

    // MARK: - Load failures

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    /// A service that never loaded in this session (e.g. the network wasn't ready at login) would stay blank:
    /// it retries on its own, waiting longer each time (2, 5, 10, 30 s, then every minute).
    private func loadFailed(_ error: Error) {
        let nsError = error as NSError
        // Not failures: a newer navigation replaced this one, or the response became a download.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        NSLog("WorkHub: %@ failed to load: %@ (%@ %ld)", config.id, nsError.localizedDescription,
              nsError.domain, nsError.code)
        guard !hasLoaded else { return }
        retryWork?.cancel()
        let delays: [TimeInterval] = [2, 5, 10, 30]
        let delay = retryCount < delays.count ? delays[retryCount] : 60
        retryCount += 1
        let work = DispatchWorkItem { [weak self] in self?.reloadHome() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Network back, or the service was selected: if it never loaded, it tries again right away.
    func retryIfNeverLoaded() {
        guard !hasLoaded, !webView.isLoading else { return }
        retryWork?.cancel()
        reloadHome()
    }

    func reloadHome() {
        _ = webView.load(URLRequest(url: config.url))
    }

    /// Signs out of the service: clears cookies and data for its domains, then reloads.
    /// Services on the same domain (e.g. Gmail and Calendar) sign out together.
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

    /// Shuts down the service when it is removed in Settings (frees the page and processes).
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

    /// Login completed in a popup that landed on the service's page:
    /// the page opens in the main view (cookies are shared, so you're already signed in).
    func finishLogin(at url: URL) {
        wasOffHome = false
        _ = webView.load(URLRequest(url: url))
        app?.refreshSiblings(of: self)
        app?.show(service: self)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // reload() does nothing if no page was ever committed: in that case load the service again.
        if webView.url == nil { reloadHome() } else { _ = webView.reload() }
    }

    // MARK: - Service icon

    private func fetchIconIfNeeded() {
        // Only once per launch and only on the service's page (not on Google's login page).
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

    // MARK: - Windows, files, permissions

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let address = url?.absoluteString ?? ""
        let blank = address.isEmpty || address == "about:blank"
        if blank || isAuthHost(url?.host) {
            // OAuth login popup (or a blank window that will be filled via script)
            let popup = PopupWindow(configuration: configuration, owner: self, showImmediately: !blank)
            popups.append(popup)
            return popup.webView
        }
        if let url = url { NSWorkspace.shared.open(url) }   // all other links: default browser
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

    // Page dialogs (alert, confirm, prompt): a sheet attached to the main window,
    // over the service that asks for it, so the other windows stay usable.
    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        alert.messageText = config.name
        guard let app = app, webView.window != nil else {
            completion(alert.runModal())
            return
        }
        app.show(service: self)
        alert.beginSheetModal(for: app.window, completionHandler: completion)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    // Microphone/camera (Slack huddles, WhatsApp voice notes). macOS still asks for permission the first time.
    // Granted without asking only to the service itself; for other sites (third-party scripts, redirects)
    // WebKit asks for confirmation.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let ownService = origin.protocol == "https" && baseDomain(origin.host) == baseDomain(config.url.host)
        decisionHandler(ownService ? .grant : .prompt)
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
        // Bounces the Downloads stack in the Dock, like Safari
        DistributedNotificationCenter.default().post(name: Notification.Name("com.apple.DownloadFileFinished"),
                                                     object: url.path)
        Notifier.shared.show(identifier: "download|\(url.path)", serviceId: config.id, serviceName: config.name,
                             jsId: nil, title: "Download complete", body: url.lastPathComponent, silent: true)
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

/// Secondary window for login popups (e.g. "Sign in with Google" on Claude or ChatGPT).
/// If a blank popup ends up on an external site, the link goes to the browser and the popup closes.
final class PopupWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let window: NSWindow
    let webView: WKWebView
    weak var owner: ServiceController?
    private var trusted: Bool
    private var authSeen: Bool      // the popup has gone through a login page
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
        // Login finished: the service's page must not be shown in the popup.
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

    // The "classic" OAuth popup closes itself with window.close() once login completes.
    func webViewDidClose(_ webView: WKWebView) {
        close()
    }

    // Login finished on a service page (e.g. Gmail's "Sign in" → mail.google.com):
    // the page moves to the main view and the popup closes.
    // The short delay lets OAuth popups that reply to the main page close on their own.
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
