import Foundation

struct NotificationSettings: Codable, Equatable {
    var pausedUntil: Double?          // secondi dal 1970; nil = notifiche attive
    var hideContent = false           // mostra solo "Nuova notifica" (utile in condivisione schermo)
    var silenceDuringFocus = false    // durante il focus solo i servizi con allowDuringFocus

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pausedUntil = try? c.decode(Double.self, forKey: .pausedUntil)
        hideContent = (try? c.decode(Bool.self, forKey: .hideContent)) ?? false
        silenceDuringFocus = (try? c.decode(Bool.self, forKey: .silenceDuringFocus)) ?? false
    }

    var isPaused: Bool {
        guard let until = pausedUntil else { return false }
        return Date().timeIntervalSince1970 < until
    }
}

struct FocusSettings: Codable, Equatable {
    var focusMinutes = 25
    var breakMinutes = 5
    var longBreakMinutes = 15
    var longBreakEvery = 0       // 0 = nessuna pausa lunga; altrimenti ogni N sessioni
    var autoStart = true         // la fase successiva parte da sola
    var chime = false            // suono breve a fine fase

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = (try? c.decode(Int.self, forKey: .focusMinutes)) ?? 25
        breakMinutes = (try? c.decode(Int.self, forKey: .breakMinutes)) ?? 5
        longBreakMinutes = (try? c.decode(Int.self, forKey: .longBreakMinutes)) ?? 15
        longBreakEvery = (try? c.decode(Int.self, forKey: .longBreakEvery)) ?? 0
        autoStart = (try? c.decode(Bool.self, forKey: .autoStart)) ?? true
        chime = (try? c.decode(Bool.self, forKey: .chime)) ?? false
    }
}

struct AppSettings: Codable, Equatable {
    var version = 1
    var services: [ServiceConfig] = defaultServices
    var notifications = NotificationSettings()
    var focus = FocusSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        services = (try? c.decode([ServiceConfig].self, forKey: .services)) ?? defaultServices
        notifications = (try? c.decode(NotificationSettings.self, forKey: .notifications)) ?? NotificationSettings()
        focus = (try? c.decode(FocusSettings.self, forKey: .focus)) ?? FocusSettings()
    }

    /// Corregge valori non validi (URL non web, id doppi, durate fuori scala).
    func sanitized() -> AppSettings {
        var copy = self
        var seen = Set<String>()
        copy.services = services.compactMap { service in
            guard let scheme = service.url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  service.url.host != nil, !seen.contains(service.id) else { return nil }
            seen.insert(service.id)
            var fixed = service
            let name = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
            fixed.name = name.isEmpty ? (service.url.host ?? service.id) : String(name.prefix(40))
            return fixed
        }
        copy.focus.focusMinutes = min(max(focus.focusMinutes, 1), 180)
        copy.focus.breakMinutes = min(max(focus.breakMinutes, 1), 60)
        copy.focus.longBreakMinutes = min(max(focus.longBreakMinutes, 1), 90)
        copy.focus.longBreakEvery = min(max(focus.longBreakEvery, 0), 12)
        return copy
    }
}

/// Impostazioni in ~/Library/Application Support/WorkHub/settings.json.
final class SettingsStore {
    private(set) var settings: AppSettings
    private let fileURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved.sanitized()
        } else {
            settings = AppSettings()
        }
    }

    func update(_ new: AppSettings) {
        settings = new.sanitized()
        save()
    }

    /// Le impostazioni in JSON (per la pagina Impostazioni).
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(settings), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
