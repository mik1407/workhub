import Cocoa
import WebKit

/// Pannello Todos: pagina Resources/todos.html.
/// I dati vivono in ~/Library/Application Support/WorkHub/todos.json, salvati a ogni modifica.
final class TodoPanel {
    static let width = LocalPanel.width

    let panel: LocalPanel
    var webView: WKWebView { panel.webView }
    /// Ultimo stato salvato (JSON), usato per promemoria e badge.
    private(set) var lastState: String
    /// Chiamato a ogni salvataggio con lo stato completo.
    var onSaved: ((String) -> Void)?
    private let fileURL: URL
    private var loaded = false
    private var queued: [String] = []

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("todos.json")

        // I dati salvati arrivano alla pagina prima che parta il suo script.
        var saved = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "null"
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if Self.isReadable(saved) {
                // Copia di sicurezza dello stato all'avvio: todos.json.bak
                let backup = folder.appendingPathComponent("todos.json.bak")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            } else {
                // La pagina partirebbe vuota e al primo salvataggio sovrascriverebbe il file: lo mette da parte.
                keepBrokenCopy(of: fileURL)
                saved = "null"
            }
        }
        lastState = saved
        panel = LocalPanel(page: "todos", handler: "todos",
                           startupScript: "window.__todoData = \(LocalPanel.jsString(saved));")
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

    /// Mostra ed evidenzia un todo (notifica cliccata).
    func reveal(_ id: String) {
        runWhenLoaded("window.todosReveal && window.todosReveal(\(LocalPanel.jsString(id)))")
    }

    /// Azione dalla notifica: "done" oppure "snooze" (un'ora).
    func apply(_ action: String, to id: String) {
        runWhenLoaded("window.todosApply && window.todosApply({id: \(LocalPanel.jsString(id)), action: \(LocalPanel.jsString(action))})")
    }

    /// Lo stesso controllo della pagina: un oggetto JSON con l'elenco "todos".
    static func isReadable(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return object["todos"] is [Any]
    }

    /// Se l'app è stata aperta da una notifica la pagina potrebbe non essere ancora pronta.
    private func runWhenLoaded(_ script: String) {
        if loaded { panel.run(script) } else { queued.append(script) }
    }
}
