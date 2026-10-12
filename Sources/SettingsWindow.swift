import Cocoa
import WebKit

/// Settings window (⌘,): page Resources/settings.html.
/// The page sends {action: "save" | "resetData" | "changeIcon" | "resetIcon", …}; the app replies with settingsUpdate.
final class SettingsWindow: NSObject {
    let window: NSWindow
    private let panel = LocalPanel(page: "settings", handler: "settings")
    var onMessage: (([String: Any]) -> Void)?
    var onLoad: (() -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = panel.webView
        applyWindowTheme()
        window.center()
        _ = window.setFrameAutosaveName("WorkHubSettings")
        panel.onMessage = { [weak self] body in
            guard let message = body as? [String: Any] else { return }
            self?.onMessage?(message)
        }
        panel.onLoad = { [weak self] in self?.onLoad?() }
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applyTheme() {
        applyWindowTheme()
        panel.applyTheme()
    }

    /// Title bar and background matching the page.
    private func applyWindowTheme() {
        window.appearance = NSAppearance(named: Theme.isLight ? .aqua : .darkAqua)
        window.backgroundColor = Theme.content
    }

    func push(_ payload: String) {
        panel.run("window.settingsUpdate && window.settingsUpdate(\(payload))")
    }
}
