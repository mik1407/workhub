import Cocoa
import WebKit

/// Snippets panel: page Resources/snippets.html. Text you paste often (phone number, address, IBAN…):
/// one click copies it to the clipboard.
/// The data lives in ~/Library/Application Support/WorkHub/snippets.json, saved on every change.
final class SnippetsPanel {
    let panel: LocalPanel
    var webView: WKWebView { panel.webView }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("snippets.json")

        // The saved snippets reach the page before its script runs.
        var saved = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "null"
        if FileManager.default.fileExists(atPath: fileURL.path), !Self.isReadable(saved) {
            keepBrokenCopy(of: fileURL)   // the page would start empty and overwrite it: set it aside
            saved = "null"
        }
        panel = LocalPanel(page: "snippets", handler: "snippets",
                           startupScript: "window.__snippetData = \(LocalPanel.jsString(saved));",
                           servicesTouchBar: true)
        panel.onMessage = { body in
            guard let message = body as? [String: Any] else { return }
            switch message["action"] as? String {
            case "save"?:
                if let json = message["data"] as? String, Self.isReadable(json) {
                    try? json.data(using: .utf8)?.write(to: fileURL, options: .atomic)
                }
            case "copy"?:
                if let text = message["text"] as? String { Self.copy(text) }
            default:
                break
            }
        }
    }

    /// Puts the text on the clipboard, ready to paste anywhere.
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// The same check as the page: a JSON object with the "snippets" list.
    static func isReadable(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["snippets"] is [Any]
    }

    /// Panel opened: keeps the keyboard in the form if one is open.
    func focus() {
        panel.run("window.snippetsFocus && window.snippetsFocus()")
    }
}
