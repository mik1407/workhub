import Cocoa
import UniformTypeIdentifiers

/// Settings window: messages from the page, saving, service icons.
extension AppController {
    // MARK: - Settings

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
            if store.settings != incoming { pushSettings() }   // values were corrected: the page resyncs
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
        if now.appearance != previous.appearance { applyTheme() }
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

    /// State for the Settings page: settings, catalog, current icons.
    func pushSettings() {
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
            "multiPartSuffixes": multiPartSuffixes.sorted(),
            "separateSessionsAvailable": separateSessionsAvailable,
            "now": Date().timeIntervalSince1970,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: extra),
              let extraJSON = String(data: data, encoding: .utf8) else { return }
        settingsWindow.push("{\"settings\":\(store.json),\"extra\":\(extraJSON)}")
    }
}
