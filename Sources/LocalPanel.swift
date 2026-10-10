import Cocoa
import WebKit

/// Pannello laterale con una pagina locale (Resources/<page>.html) che dialoga con l'app via messaggi.
/// Usato da Todos e Focus.
final class LocalPanel: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let width: CGFloat = 360

    let webView: WKWebView
    var onMessage: ((Any) -> Void)?
    var onLoad: (() -> Void)?
    private let page: String
    private let startupScript: String?

    init(page: String, handler: String, startupScript: String? = nil) {
        self.page = page
        self.startupScript = startupScript
        let content = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.alphaValue = 0   // invisibile finché la pagina non è pronta (niente lampo bianco)
        super.init()
        installScripts()
        content.add(self, name: handler)
        webView.navigationDelegate = self
        if let url = Bundle.main.url(forResource: page, withExtension: "html") {
            _ = webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func run(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Cambio di tema: la pagina aperta si aggiorna subito, e se viene ricaricata parte già col tema giusto.
    func applyTheme() {
        installScripts()
        run(Self.themeScript)
    }

    private static var themeScript: String {
        "document.documentElement.dataset.theme = '\(Theme.isLight ? "light" : "dark")';"
    }

    /// Script eseguiti all'apertura della pagina: il tema (niente lampo dei colori dell'altro tema)
    /// ed eventuali dati iniziali.
    private func installScripts() {
        let content = webView.configuration.userContentController
        content.removeAllUserScripts()
        var source = Self.themeScript
        if let startupScript = startupScript { source += "\n" + startupScript }
        content.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        onMessage?(message.body)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.alphaValue = 1
        onLoad?()
    }

    // Il pannello mostra solo la propria pagina: i link vanno al browser, i file trascinati vengono ignorati.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL && url.lastPathComponent == "\(page).html" {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    /// Stringa Swift → letterale stringa JavaScript con escaping corretto.
    static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return "null" }
        return String(json.dropFirst().dropLast())
    }
}
