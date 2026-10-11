import Foundation

/// Come leggere il numero di non letti di un servizio.
enum BadgeMode: String, Codable {
    case none
    case title   // "(3)" nel titolo della pagina (WhatsApp, Teams, Telegram…)
    case gmail   // "(3)" nel titolo, mantenuto quando apri una mail
    case slack   // selettori DOM di Slack, con fallback sul titolo
}

/// Un servizio della sidebar. Salvato in settings.json, modificabile da Impostazioni > Services.
struct ServiceConfig: Codable, Equatable {
    var id: String
    var name: String
    var url: URL
    var badge: BadgeMode
    var countInDock = true          // il suo numero entra nel badge del Dock
    var notify = true               // notifiche macOS
    var sound = true                // suono delle notifiche
    var allowDuringFocus = false    // notifiche anche durante il focus (se il silenzio è attivo)

    init(id: String, name: String, url: URL, badge: BadgeMode) {
        self.id = id
        self.name = name
        self.url = url
        self.badge = badge
    }

    // Lettura tollerante: i campi mancanti prendono il valore predefinito.
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
    }
}

/// Servizi al primo avvio (ordine della sidebar = scorciatoie ⌘1…⌘9).
let defaultServices: [ServiceConfig] = [
    ServiceConfig(id: "gmail", name: "Gmail", url: URL(string: "https://mail.google.com/mail/u/0/")!, badge: .gmail),
    ServiceConfig(id: "slack", name: "Slack", url: URL(string: "https://app.slack.com/client")!, badge: .slack),
    ServiceConfig(id: "calendar", name: "Google Calendar", url: URL(string: "https://calendar.google.com/calendar/u/0/r")!, badge: .none),
    ServiceConfig(id: "claude", name: "Claude", url: URL(string: "https://claude.ai/new")!, badge: .none),
    ServiceConfig(id: "chatgpt", name: "ChatGPT", url: URL(string: "https://chatgpt.com/")!, badge: .none),
    ServiceConfig(id: "whatsapp", name: "WhatsApp", url: URL(string: "https://web.whatsapp.com/")!, badge: .title),
]

/// Catalogo di Impostazioni > Services > Add service.
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

/// Host di login usati nei popup OAuth ("Accedi con Google/Apple/Microsoft").
/// Questi popup restano dentro l'app; tutti gli altri link esterni si aprono nel browser.
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

/// Suffissi pubblici di più parti: lì il sito ha una parte in più (bbc.co.uk, non co.uk).
/// Non è l'elenco completo (Public Suffix List), ma copre i paesi e gli hosting più comuni.
let multiPartSuffixes: Set<String> = [
    "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "ltd.uk", "plc.uk",
    "com.au", "net.au", "org.au", "edu.au", "gov.au", "co.nz", "org.nz",
    "co.jp", "ne.jp", "or.jp", "co.kr", "co.in", "co.za", "co.il", "co.id", "co.th",
    "com.br", "com.mx", "com.ar", "com.co", "com.tr", "com.cn", "com.hk", "com.tw", "com.sg", "com.my",
    "com.ph", "com.pe", "com.uy", "com.ec", "com.pl", "com.es",
    "github.io", "gitlab.io", "pages.dev", "vercel.app", "netlify.app", "herokuapp.com", "web.app",
    "firebaseapp.com", "appspot.com", "azurewebsites.net", "cloudfront.net", "blogspot.com",
]

/// Dominio del sito: mail.google.com -> google.com, news.bbc.co.uk -> bbc.co.uk.
/// Gli indirizzi IP restano interi. La pagina Impostazioni applica la stessa regola.
func baseDomain(_ host: String?) -> String {
    guard let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
          !host.isEmpty else { return "" }
    let parts = host.split(separator: ".")
    if host.contains(":") || parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return host }
    let keep = multiPartSuffixes.contains(parts.suffix(2).joined(separator: ".")) ? 3 : 2
    return parts.suffix(keep).joined(separator: ".")
}

/// Suffisso user agent identico a Safari, letto dalla versione di Safari installata.
/// WebKit lo aggiunge al proprio UA di base, così i servizi vedono un Safari standard.
func safariUserAgentSuffix() -> String {
    let version = Bundle(path: "/Applications/Safari.app")?
        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "18.0"
    return "Version/\(version) Safari/605.1.15"
}
