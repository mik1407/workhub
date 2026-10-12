import Cocoa

// WorkHub logic tests, without opening any windows: ./build.sh test
// Compiled together with Sources/ (except main.swift). Each check prints OK or FAIL;
// the process exits with 1 if at least one fails. The first argument is a temporary folder.

var failures = 0

func check(_ condition: Bool, _ label: String, line: UInt = #line) {
    if condition {
        print("  OK    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)  (Tests/main.swift:\(line))")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
    check(actual == expected, actual == expected ? label : "\(label): \(actual) instead of \(expected)", line: line)
}

func section(_ name: String) { print("\n\(name)") }

func settings(_ json: String) -> AppSettings {
    (try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)))?.sanitized() ?? AppSettings()
}

let temp = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())

// MARK: - Domains

section("baseDomain")
equal(baseDomain("mail.google.com"), "google.com", "subdomain")
equal(baseDomain("Calendar.Google.COM"), "google.com", "uppercase")
equal(baseDomain("google.com"), "google.com", "already a base domain")
equal(baseDomain("news.bbc.co.uk"), "bbc.co.uk", "two-part suffix (co.uk)")
equal(baseDomain("bbc.co.uk"), "bbc.co.uk", "co.uk without subdomain")
equal(baseDomain("shop.example.com.au"), "example.com.au", "com.au")
equal(baseDomain("alice.github.io"), "alice.github.io", "hosting: each user is a separate site")
equal(baseDomain("192.168.1.10"), "192.168.1.10", "whole IPv4 address")
equal(baseDomain("::1"), "::1", "whole IPv6 address")
equal(baseDomain("localhost"), "localhost", "name without dots")
equal(baseDomain("mail.google.com."), "google.com", "trailing dot")
equal(baseDomain(nil), "", "missing host")
check(baseDomain("a.co.uk") != baseDomain("b.co.uk"), "two different .co.uk sites stay different")

section("isAuthHost")
check(isAuthHost("accounts.google.com"), "Google login")
check(isAuthHost("eu.login.microsoftonline.com"), "subdomain of a login host")
check(!isAuthHost("google.com"), "non-login domain")
check(!isAuthHost("evil-accounts.google.com.example.org"), "host containing the name but on another site")
check(!isAuthHost(nil), "missing host")

// MARK: - Settings

section("Settings: tolerant decoding")
let mixed = settings("""
{"services":[{"id":"gmail","name":"Gmail","url":"https://mail.google.com/","badge":"gmail"},
             {"id":"broken","name":"Broken","url":""},
             {"name":"No id","url":"https://example.com/"},
             {"id":"notion","name":"Notion","url":"https://www.notion.so/","badge":"strange"}],
 "appearance":"light"}
""")
equal(mixed.services.map(\.id), ["gmail", "notion"], "malformed services dropped, the others kept")
equal(mixed.services.last?.badge, .title, "unknown badge -> title")
equal(mixed.services.first?.notify, true, "missing field -> default value")
equal(mixed.appearance, .light, "theme read")
equal(settings(#"{"services":[{"id":"x","url":""}]}"#).services.map(\.id), defaultServices.map(\.id),
      "no valid service -> default services")
equal(settings(#"{"appearance":"purple"}"#).appearance, .dark, "unknown theme -> dark")
equal(settings("{}").focus.focusMinutes, 25, "empty file -> default values")

section("Settings: value correction")
let fixed = settings("""
{"services":[{"id":"a","name":"   ","url":"https://app.example.com/"},
             {"id":"a","name":"Duplicate","url":"https://other.example.com/"},
             {"id":"ftp","name":"FTP","url":"ftp://files.example.com/"},
             {"id":"long","name":"\(String(repeating: "x", count: 60))","url":"https://long.example.com/"}],
 "focus":{"focusMinutes":0,"breakMinutes":500,"longBreakMinutes":-3,"longBreakEvery":50}}
""")
equal(fixed.services.map(\.id), ["a", "long"], "duplicate id and non-web address dropped")
equal(fixed.services.first?.name, "app.example.com", "empty name -> host")
equal(fixed.services.last?.name.count, 40, "name too long cut to 40")
equal(fixed.focus.focusMinutes, 1, "focus at least 1 minute")
equal(fixed.focus.breakMinutes, 60, "break at most 60 minutes")
equal(fixed.focus.longBreakMinutes, 1, "long break at least 1 minute")
equal(fixed.focus.longBreakEvery, 12, "long break at most every 12 sessions")

section("Paused notifications")
var rules = NotificationSettings()
check(!rules.isPaused, "not paused")
rules.pausedUntil = Date().timeIntervalSince1970 + 3600
check(rules.isPaused, "pause in progress")
rules.pausedUntil = Date().timeIntervalSince1970 - 10
check(!rules.isPaused, "pause expired")

section("Unreadable files")
let broken = temp.appendingPathComponent("settings.json")
try? "{ not json".write(to: broken, atomically: true, encoding: .utf8)
keepBrokenCopy(of: broken)
let copies = (try? FileManager.default.contentsOfDirectory(atPath: temp.path))?.filter { $0.hasPrefix("settings-broken-") } ?? []
equal(copies.count, 1, "copy created next to the original")
if let copy = copies.first {
    equal(try? String(contentsOf: temp.appendingPathComponent(copy), encoding: .utf8), "{ not json", "identical copy")
}

// MARK: - Todos

section("Todos")
check(TodoPanel.isReadable(#"{"todos":[]}"#), "empty list is valid")
check(!TodoPanel.isReadable("null"), "null is not valid")
check(!TodoPanel.isReadable(#"{"todos":"x"}"#), "todos is not a list")
check(!TodoPanel.isReadable("{ broken"), "broken JSON")
let now = Date().timeIntervalSince1970 * 1000
let todos = """
{"todos":[{"id":"1","due":\(now - 60_000)},{"id":"2","due":\(now - 60_000),"done":true},
          {"id":"3","due":\(now + 3_600_000)},{"id":"4"}]}
"""
equal(TodoReminders.overdueCount(in: todos), 1, "only open todos already past due")
equal(TodoReminders.overdueCount(in: "broken"), 0, "broken JSON -> 0")

// MARK: - Sounds and downloads

section("Sound names")
equal(SoundLibrary.displayName(for: URL(fileURLWithPath: "bgm_WindWithCrickets.m4a")), "Wind With Crickets", "prefix and capitals")
equal(SoundLibrary.displayName(for: URL(fileURLWithPath: "alm_Bell.caf")), "Bell", "alm_ prefix")
equal(SoundLibrary.displayName(for: URL(fileURLWithPath: "my-sound_file.mp3")), "my sound file", "hyphens and underscores")

section("Download names")
let downloads = temp.appendingPathComponent("downloads", isDirectory: true)
try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
equal(ServiceController.uniqueURL(in: downloads, filename: "report.pdf").lastPathComponent, "report.pdf", "name free")
FileManager.default.createFile(atPath: downloads.appendingPathComponent("report.pdf").path, contents: Data())
equal(ServiceController.uniqueURL(in: downloads, filename: "report.pdf").lastPathComponent, "report (1).pdf", "name taken")
FileManager.default.createFile(atPath: downloads.appendingPathComponent("report (1).pdf").path, contents: Data())
equal(ServiceController.uniqueURL(in: downloads, filename: "report.pdf").lastPathComponent, "report (2).pdf", "second duplicate")
FileManager.default.createFile(atPath: downloads.appendingPathComponent("notes").path, contents: Data())
equal(ServiceController.uniqueURL(in: downloads, filename: "notes").lastPathComponent, "notes (1)", "no extension")
equal(ServiceController.uniqueURL(in: downloads, filename: "").lastPathComponent, "download", "empty name")

// MARK: - Pages and theme

section("Text sent to pages")
for text in ["simple", "quotes \" and '", "newline\nand tab\t", "</script><b>", "emoji 🎧 and accents è"] {
    let literal = LocalPanel.jsString(text)
    let back = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String
    equal(back, text, "correct JS literal: \(text.debugDescription)")
}

section("Theme")
check(Theme.apply(.light) && Theme.isLight, "switches to light")
check(!Theme.apply(.light), "same theme: no change")
equal(Theme.content, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), "white cards in light mode")
check(Theme.apply(.dark) && !Theme.isLight, "back to dark")

section("Separate sign-in")
equal(sessionIdentifier(for: "gmail-2"), sessionIdentifier(for: "gmail-2"), "same service -> same storage on every launch")
check(sessionIdentifier(for: "gmail-2") != sessionIdentifier(for: "gmail-3"), "different services -> different storage")
check(sessionIdentifier(for: "gmail").uuidString.dropFirst(14).hasPrefix("5"), "valid name-based UUID")
let sessions = settings("""
{"services":[{"id":"wa","name":"WhatsApp","url":"https://web.whatsapp.com/"},
             {"id":"wa-2","name":"WhatsApp 2","url":"https://web.whatsapp.com/","separateSession":true}]}
""")
equal(sessions.services.map(\.separateSession), [false, true], "missing field -> shared sign-in")
equal(settings(#"{"services":[{"id":"a","url":"https://a.example.com/","separatorAfter":true},{"id":"b","url":"https://b.example.com/"}]}"#)
      .services.map(\.separatorAfter), [true, false], "separator read, missing -> none")

print(failures == 0 ? "\nAll tests passed." : "\n\(failures) tests failed.")
exit(failures == 0 ? 0 : 1)
