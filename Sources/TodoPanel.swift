import Cocoa
import WebKit

/// Todos panel: page Resources/todos.html.
/// The data lives in ~/Library/Application Support/WorkHub/todos.json, saved on every change.
final class TodoPanel {
    static let width = LocalPanel.width

    let panel: LocalPanel
    var webView: WKWebView { panel.webView }
    /// Last saved state (JSON), used for reminders and the badge.
    private(set) var lastState: String
    /// Called on every save with the full state.
    var onSaved: ((String) -> Void)?
    private let fileURL: URL
    private var loaded = false
    private var queued: [String] = []

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("todos.json")

        // The saved data reaches the page before its script starts.
        var saved = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "null"
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if Self.isReadable(saved) {
                // Backup copy of the state at launch: todos.json.bak
                let backup = folder.appendingPathComponent("todos.json.bak")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            } else {
                // The page would start empty and overwrite the file on the first save: set it aside.
                keepBrokenCopy(of: fileURL)
                saved = "null"
            }
        }
        lastState = saved
        panel = LocalPanel(page: "todos", handler: "todos",
                           startupScript: "window.__todoData = \(LocalPanel.jsString(saved));",
                           servicesTouchBar: true)
        let destination = fileURL
        panel.onMessage = { [weak self] body in
            guard let json = body as? String else { return }
            try? json.data(using: .utf8)?.write(to: destination, options: .atomic)
            self?.lastState = json
            self?.onSaved?(json)
        }
        panel.onLoad = { [weak self] in
            guard let self = self else { return }
            self.loaded = true
            self.queued.forEach { self.panel.run($0) }
            self.queued.removeAll()
        }
    }

    func focusInput() {
        runWhenLoaded("window.todosFocusInput && window.todosFocusInput()")
    }

    /// Shows and highlights a todo (notification clicked).
    func reveal(_ id: String) {
        runWhenLoaded("window.todosReveal && window.todosReveal(\(LocalPanel.jsString(id)))")
    }

    /// Action from the notification: "done" or "snooze" (one hour).
    func apply(_ action: String, to id: String) {
        runWhenLoaded("window.todosApply && window.todosApply({id: \(LocalPanel.jsString(id)), action: \(LocalPanel.jsString(action))})")
    }

    /// Same check as the page: a JSON object with a "todos" list.
    static func isReadable(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["todos"] is [Any]
    }

    /// If the app was opened from a notification, the page may not be ready yet.
    private func runWhenLoaded(_ script: String) {
        if loaded { panel.run(script) } else { queued.append(script) }
    }
}
