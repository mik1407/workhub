import Foundation

struct NotificationSettings: Codable, Equatable {
    var pausedUntil: Double?          // seconds since 1970; nil = notifications on
    var hideContent = false           // show only "New notification" (useful when screen sharing)
    var silenceDuringFocus = false    // during focus, only services with allowDuringFocus

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
    var longBreakEvery = 0       // 0 = no long break; otherwise every N sessions
    var autoStart = true         // the next phase starts on its own
    var chime = false            // short sound at the end of a phase

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

/// App theme: frame, bars, panels and Settings. Services always follow the macOS theme.
enum AppearanceMode: String, Codable {
    case dark, light
    case system   // follows macOS (light or dark)
}

struct AppSettings: Codable, Equatable {
    var version = 1
    var services: [ServiceConfig] = defaultServices
    var notifications = NotificationSettings()
    var focus = FocusSettings()
    var appearance = AppearanceMode.dark

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        // One service at a time: a malformed one is dropped, the others are kept.
        services = (try? c.decode([Lenient<ServiceConfig>].self, forKey: .services))?.compactMap { $0.value }
            ?? defaultServices
        notifications = (try? c.decode(NotificationSettings.self, forKey: .notifications)) ?? NotificationSettings()
        focus = (try? c.decode(FocusSettings.self, forKey: .focus)) ?? FocusSettings()
        appearance = (try? c.decode(AppearanceMode.self, forKey: .appearance)) ?? .dark
    }

    /// Fixes invalid values (non-web URLs, duplicate ids, out-of-range durations).
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
        if copy.services.isEmpty { copy.services = defaultServices }   // the sidebar is never left empty
        copy.focus.focusMinutes = min(max(focus.focusMinutes, 1), 180)
        copy.focus.breakMinutes = min(max(focus.breakMinutes, 1), 60)
        copy.focus.longBreakMinutes = min(max(focus.longBreakMinutes, 1), 90)
        copy.focus.longBreakEvery = min(max(focus.longBreakEvery, 0), 12)
        return copy
    }
}

/// Decodes one list element without failing the whole list: if it is malformed, value is nil.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Copies an unreadable data file next to the original
/// (e.g. settings-broken-2026-10-11-093012.json), so it is not lost when the app rewrites it.
func keepBrokenCopy(of url: URL) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let name = "\(url.deletingPathExtension().lastPathComponent)-broken-\(formatter.string(from: Date())).\(url.pathExtension)"
    try? FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
}

/// Settings in ~/Library/Application Support/WorkHub/settings.json.
final class SettingsStore {
    /// Single instance: the theme must be read at launch, before bars and panels are created.
    static let shared = SettingsStore()

    private(set) var settings: AppSettings
    private let fileURL: URL

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL) {
            if let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
                settings = saved.sanitized()
            } else {
                // Unreadable file (e.g. edited by hand): start over from the defaults,
                // but the original is kept aside instead of being overwritten on the first save.
                keepBrokenCopy(of: fileURL)
                settings = AppSettings()
            }
        } else {
            settings = AppSettings()
        }
    }

    func update(_ new: AppSettings) {
        settings = new.sanitized()
        save()
    }

    /// The settings as JSON (for the Settings page).
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
