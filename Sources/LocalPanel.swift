import Cocoa
import WebKit

/// Side panel with a local page (Resources/<page>.html) that talks to the app via messages.
/// Used by Todos and Focus.
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
        webView.alphaValue = 0   // invisible until the page is ready (no white flash)
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

    /// Theme change: the open page updates right away, and if reloaded it starts with the right theme.
    func applyTheme() {
        installScripts()
        run(Self.themeScript)
    }

    private static var themeScript: String {
        "document.documentElement.dataset.theme = '\(Theme.isLight ? "light" : "dark")';"
    }

    /// Scripts run when the page opens: the theme (no flash of the other theme's colors)
    /// and any initial data.
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

    // The panel shows only its own page: links go to the browser, dropped files are ignored.
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

    /// Swift string → JavaScript string literal with correct escaping.
    static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8) else { return "null" }
        return String(json.dropFirst().dropLast())
    }
}
