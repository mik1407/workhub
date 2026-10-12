import CryptoKit
import Foundation

/// How to read a service's unread count.
enum BadgeMode: String, Codable {
    case none
    case title   // "(3)" in the page title (WhatsApp, Teams, Telegram…)
    case gmail   // "(3)" in the title, kept when you open an email
    case slack   // Slack DOM selectors, falling back to the title
}

/// A sidebar service. Saved in settings.json, editable from Settings > Services.
struct ServiceConfig: Codable, Equatable {
    var id: String
    var name: String
    var url: URL
    var badge: BadgeMode
    var countInDock = true          // its count is included in the Dock badge
    var notify = true               // macOS notifications
    var sound = true                // notification sound
    var allowDuringFocus = false    // notify even during focus (when silencing is on)
    var separateSession = false     // own cookies and sign-in, e.g. for a second account (macOS 14+)
    var separatorAfter = false      // a separator line below its icon in the sidebar

    init(id: String, name: String, url: URL, badge: BadgeMode) {
        self.id = id
        self.name = name
        self.url = url
        self.badge = badge
    }

    // Lenient decoding: missing fields take their default value.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        name = (try? c.decode(String.self, forKey: .name)) ?? (url.host ?? id)
        badge = (try? c.decode(BadgeMode.self, forKey: .badge)) ?? .title
        countInDock = (try? c.decode(Bool.self, forKey: .countInDock)) ?? true
        notify = (try? c.decode(Bool.self, forKey: .notify)) ?? true
        sound = (try? c.decode(Bool.self, forKey: .sound)) ?? true
        allowDuringFocus = (try? c.decode(Bool.self, forKey: .allowDuringFocus)) ?? false
        separateSession = (try? c.decode(Bool.self, forKey: .separateSession)) ?? false
        separatorAfter = (try? c.decode(Bool.self, forKey: .separatorAfter)) ?? false
    }
}

/// Separate sign-in needs per-identifier website data stores, available from macOS 14.
var separateSessionsAvailable: Bool {
    if #available(macOS 14.0, *) { return true }
    return false
}

/// Identifier of a service's own session storage: derived from the service id, so it stays the same
/// across launches (the service finds its cookies and sign-in again) and differs between services.
func sessionIdentifier(for serviceId: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data("workhub.session.\(serviceId)".utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x50   // name-based UUID (version 5 layout)
    bytes[8] = (bytes[8] & 0x3f) | 0x80   // RFC 4122 variant
    return NSUUID(uuidBytes: bytes) as UUID
}

/// Services on first launch (sidebar order = shortcuts ⌘1…⌘9).
let defaultServices: [ServiceConfig] = [
    ServiceConfig(id: "gmail", name: "Gmail", url: URL(string: "https://mail.google.com/mail/u/0/")!, badge: .gmail),
    ServiceConfig(id: "slack", name: "Slack", url: URL(string: "https://app.slack.com/client")!, badge: .slack),
    ServiceConfig(id: "calendar", name: "Google Calendar", url: URL(string: "https://calendar.google.com/calendar/u/0/r")!, badge: .none),
    ServiceConfig(id: "claude", name: "Claude", url: URL(string: "https://claude.ai/new")!, badge: .none),
    ServiceConfig(id: "chatgpt", name: "ChatGPT", url: URL(string: "https://chatgpt.com/")!, badge: .none),
    ServiceConfig(id: "whatsapp", name: "WhatsApp", url: URL(string: "https://web.whatsapp.com/")!, badge: .title),
]

/// Catalog for Settings > Services > Add service.
let serviceCatalog: [ServiceConfig] = [
    ServiceConfig(id: "gmail", name: "Gmail", url: URL(string: "https://mail.google.com/mail/u/0/")!, badge: .gmail),
    ServiceConfig(id: "calendar", name: "Google Calendar", url: URL(string: "https://calendar.google.com/calendar/u/0/r")!, badge: .none),
    ServiceConfig(id: "drive", name: "Google Drive", url: URL(string: "https://drive.google.com/")!, badge: .none),
    ServiceConfig(id: "outlook", name: "Outlook", url: URL(string: "https://outlook.office.com/mail/")!, badge: .title),
    ServiceConfig(id: "teams", name: "Microsoft Teams", url: URL(string: "https://teams.microsoft.com/")!, badge: .title),
    ServiceConfig(id: "slack", name: "Slack", url: URL(string: "https://app.slack.com/client")!, badge: .slack),
    ServiceConfig(id: "whatsapp", name: "WhatsApp", url: URL(string: "https://web.whatsapp.com/")!, badge: .title),
    ServiceConfig(id: "telegram", name: "Telegram", url: URL(string: "https://web.telegram.org/a/")!, badge: .title),
    ServiceConfig(id: "discord", name: "Discord", url: URL(string: "https://discord.com/app")!, badge: .title),
    ServiceConfig(id: "messenger", name: "Messenger", url: URL(string: "https://www.messenger.com/")!, badge: .title),
    ServiceConfig(id: "linkedin", name: "LinkedIn", url: URL(string: "https://www.linkedin.com/messaging/")!, badge: .title),
    ServiceConfig(id: "notion", name: "Notion", url: URL(string: "https://www.notion.so/")!, badge: .none),
    ServiceConfig(id: "linear", name: "Linear", url: URL(string: "https://linear.app/")!, badge: .none),
    ServiceConfig(id: "asana", name: "Asana", url: URL(string: "https://app.asana.com/")!, badge: .none),
    ServiceConfig(id: "trello", name: "Trello", url: URL(string: "https://trello.com/")!, badge: .none),
    ServiceConfig(id: "figma", name: "Figma", url: URL(string: "https://www.figma.com/files")!, badge: .none),
    ServiceConfig(id: "claude", name: "Claude", url: URL(string: "https://claude.ai/new")!, badge: .none),
    ServiceConfig(id: "chatgpt", name: "ChatGPT", url: URL(string: "https://chatgpt.com/")!, badge: .none),
    ServiceConfig(id: "gemini", name: "Gemini", url: URL(string: "https://gemini.google.com/app")!, badge: .none),
]

/// Login hosts used in OAuth popups ("Sign in with Google/Apple/Microsoft").
/// These popups stay inside the app; all other external links open in the browser.
private let authHosts: [String] = [
    "accounts.google.com",
    "appleid.apple.com",
    "auth.openai.com",
    "auth0.openai.com",
    "login.microsoftonline.com",
    "login.live.com",
]

func isAuthHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return authHosts.contains { host == $0 || host.hasSuffix("." + $0) }
}

/// Multi-part public suffixes: there the site has one extra part (bbc.co.uk, not co.uk).
/// Not the full list (Public Suffix List), but it covers the most common countries and hosts.
let multiPartSuffixes: Set<String> = [
    "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk",
    "com.au", "net.au", "org.au", "edu.au", "gov.au", "co.nz", "org.nz",
    "co.jp", "ne.jp", "or.jp", "co.kr", "co.in", "co.za", "co.il", "co.id", "co.th",
    "com.br", "com.mx", "com.ar", "com.co", "com.tr", "com.cn", "com.hk", "com.tw", "com.sg", "com.my",
    "com.ph", "com.pe", "com.uy", "com.ec", "com.pl", "com.es",
    "github.io", "gitlab.io", "pages.dev", "vercel.app", "netlify.app", "herokuapp.com", "web.app",
    "firebaseapp.com", "appspot.com", "azurewebsites.net", "cloudfront.net", "blogspot.com",
]

/// Site domain: mail.google.com -> google.com, news.bbc.co.uk -> bbc.co.uk.
/// IP addresses are kept whole. The Settings page applies the same rule.
func baseDomain(_ host: String?) -> String {
    guard let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
          !host.isEmpty else { return "" }
    let parts = host.split(separator: ".")
    if host.contains(":") || parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return host }
    let keep = multiPartSuffixes.contains(parts.suffix(2).joined(separator: ".")) ? 3 : 2
    return parts.suffix(keep).joined(separator: ".")
}

/// User agent suffix identical to Safari's, read from the installed Safari version.
/// WebKit appends it to its own base UA, so services see a standard Safari.
func safariUserAgentSuffix() -> String {
    let version = Bundle(path: "/Applications/Safari.app")?
        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "18.0"
    return "Version/\(version) Safari/605.1.15"
}
