import Cocoa

// Test della logica di WorkHub, senza aprire finestre: ./build.sh test
// Compilati insieme a Sources/ (tranne main.swift). Ogni controllo stampa OK o FAIL;
// il processo esce con 1 se almeno uno fallisce. Il primo argomento è una cartella temporanea.

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
    check(actual == expected, actual == expected ? label : "\(label): \(actual) invece di \(expected)", line: line)
}

func section(_ name: String) { print("\n\(name)") }

func settings(_ json: String) -> AppSettings {
    (try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)))?.sanitized() ?? AppSettings()
}

let temp = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())

// MARK: - Domini

section("baseDomain")
equal(baseDomain("mail.google.com"), "google.com", "sottodominio")
equal(baseDomain("Calendar.Google.COM"), "google.com", "maiuscole")
equal(baseDomain("google.com"), "google.com", "dominio già base")
equal(baseDomain("news.bbc.co.uk"), "bbc.co.uk", "suffisso di due parti (co.uk)")
equal(baseDomain("bbc.co.uk"), "bbc.co.uk", "co.uk senza sottodominio")
equal(baseDomain("shop.example.com.au"), "example.com.au", "com.au")
equal(baseDomain("alice.github.io"), "alice.github.io", "hosting: ogni utente è un sito")
equal(baseDomain("192.168.1.10"), "192.168.1.10", "indirizzo IPv4 intero")
equal(baseDomain("::1"), "::1", "indirizzo IPv6 intero")
equal(baseDomain("localhost"), "localhost", "nome senza punti")
equal(baseDomain("mail.google.com."), "google.com", "punto finale")
equal(baseDomain(nil), "", "host mancante")
check(baseDomain("a.co.uk") != baseDomain("b.co.uk"), "due siti .co.uk diversi restano diversi")

section("isAuthHost")
check(isAuthHost("accounts.google.com"), "login Google")
check(isAuthHost("eu.login.microsoftonline.com"), "sottodominio di un host di login")
check(!isAuthHost("google.com"), "dominio non di login")
check(!isAuthHost("evil-accounts.google.com.example.org"), "host che contiene il nome ma è un altro sito")
check(!isAuthHost(nil), "host mancante")

// MARK: - Impostazioni

section("Impostazioni: lettura tollerante")
let mixed = settings("""
{"services":[{"id":"gmail","name":"Gmail","url":"https://mail.google.com/","badge":"gmail"},
             {"id":"rotto","name":"Rotto","url":""},
             {"name":"Senza id","url":"https://example.com/"},
             {"id":"notion","name":"Notion","url":"https://www.notion.so/","badge":"strano"}],
 "appearance":"light"}
""")
equal(mixed.services.map(\.id), ["gmail", "notion"], "servizi malformati scartati, gli altri restano")
equal(mixed.services.last?.badge, .title, "badge sconosciuto -> title")
equal(mixed.services.first?.notify, true, "campo mancante -> valore predefinito")
equal(mixed.appearance, .light, "tema letto")
equal(settings(#"{"services":[{"id":"x","url":""}]}"#).services.map(\.id), defaultServices.map(\.id),
      "nessun servizio valido -> servizi iniziali")
equal(settings(#"{"appearance":"viola"}"#).appearance, .dark, "tema sconosciuto -> dark")
equal(settings("{}").focus.focusMinutes, 25, "file vuoto -> valori iniziali")

section("Impostazioni: correzione dei valori")
let fixed = settings("""
{"services":[{"id":"a","name":"   ","url":"https://app.example.com/"},
             {"id":"a","name":"Doppio","url":"https://other.example.com/"},
             {"id":"ftp","name":"FTP","url":"ftp://files.example.com/"},
             {"id":"long","name":"\(String(repeating: "x", count: 60))","url":"https://long.example.com/"}],
 "focus":{"focusMinutes":0,"breakMinutes":500,"longBreakMinutes":-3,"longBreakEvery":50}}
""")
equal(fixed.services.map(\.id), ["a", "long"], "id doppio e indirizzo non web scartati")
equal(fixed.services.first?.name, "app.example.com", "nome vuoto -> host")
equal(fixed.services.last?.name.count, 40, "nome troppo lungo tagliato a 40")
equal(fixed.focus.focusMinutes, 1, "focus minimo 1 minuto")
equal(fixed.focus.breakMinutes, 60, "pausa massima 60 minuti")
equal(fixed.focus.longBreakMinutes, 1, "pausa lunga minimo 1 minuto")
equal(fixed.focus.longBreakEvery, 12, "pausa lunga al massimo ogni 12 sessioni")

section("Notifiche in pausa")
var rules = NotificationSettings()
check(!rules.isPaused, "nessuna pausa")
rules.pausedUntil = Date().timeIntervalSince1970 + 3600
check(rules.isPaused, "pausa in corso")
rules.pausedUntil = Date().timeIntervalSince1970 - 10
check(!rules.isPaused, "pausa scaduta")

section("File illeggibili")
let broken = temp.appendingPathComponent("settings.json")
try? "{ non è json".write(to: broken, atomically: true, encoding: .utf8)
keepBrokenCopy(of: broken)
let copies = (try? FileManager.default.contentsOfDirectory(atPath: temp.path))?.filter { $0.hasPrefix("settings-broken-") } ?? []
equal(copies.count, 1, "copia creata accanto all'originale")
if let copy = copies.first {
    equal(try? String(contentsOf: temp.appendingPathComponent(copy), encoding: .utf8), "{ non è json", "copia identica")
}

// MARK: - Todo

section("Todos")
check(TodoPanel.isReadable(#"{"todos":[]}"#), "elenco vuoto valido")
check(!TodoPanel.isReadable("null"), "null non valido")
check(!TodoPanel.isReadable(#"{"todos":"x"}"#), "todos non è un elenco")
check(!TodoPanel.isReadable("{ rotto"), "JSON rotto")
let now = Date().timeIntervalSince1970 * 1000
let todos = """
{"todos":[{"id":"1","due":\(now - 60_000)},{"id":"2","due":\(now - 60_000),"done":true},
          {"id":"3","due":\(now + 3_600_000)},{"id":"4"}]}
"""
equal(TodoReminders.overdueCount(in: todos), 1, "solo i todo aperti già scaduti")
equal(TodoReminders.overdueCount(in: "rotto"), 0, "JSON rotto -> 0")

// MARK: - Suoni e download

section("Nomi dei suoni")
equal(SoundLibrary.displayName(for: URL(fileURLWithPath: "bgm_WindWithCrickets.m4a")), "Wind With Crickets", "prefisso e maiuscole")
equal(SoundLibrary.displayName(for: URL(fileURLWithPath: "alm_Bell.caf")), "Bell", "prefisso alm_")
equal(SoundLibrary.displayName(for: URL(fileURLWithPath: "my-sound_file.mp3")), "my sound file", "trattini e underscore")

section("Nomi dei download")
let downloads = temp.appendingPathComponent("downloads", isDirectory: true)
try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
equal(ServiceController.uniqueURL(in: downloads, filename: "report.pdf").lastPathComponent, "report.pdf", "nome libero")
FileManager.default.createFile(atPath: downloads.appendingPathComponent("report.pdf").path, contents: Data())
equal(ServiceController.uniqueURL(in: downloads, filename: "report.pdf").lastPathComponent, "report (1).pdf", "nome occupato")
FileManager.default.createFile(atPath: downloads.appendingPathComponent("report (1).pdf").path, contents: Data())
equal(ServiceController.uniqueURL(in: downloads, filename: "report.pdf").lastPathComponent, "report (2).pdf", "secondo duplicato")
FileManager.default.createFile(atPath: downloads.appendingPathComponent("notes").path, contents: Data())
equal(ServiceController.uniqueURL(in: downloads, filename: "notes").lastPathComponent, "notes (1)", "senza estensione")
equal(ServiceController.uniqueURL(in: downloads, filename: "").lastPathComponent, "download", "nome vuoto")

// MARK: - Pagine e tema

section("Testo verso le pagine")
for text in ["semplice", "virgolette \" e '", "a capo\ne tab\t", "</script><b>", "emoji 🎧 e accenti è"] {
    let literal = LocalPanel.jsString(text)
    let back = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String
    equal(back, text, "letterale JS corretto: \(text.debugDescription)")
}

section("Tema")
check(Theme.apply(.light) && Theme.isLight, "passa al chiaro")
check(!Theme.apply(.light), "stesso tema: nessun cambio")
equal(Theme.content, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), "card bianche nel chiaro")
check(Theme.apply(.dark) && !Theme.isLight, "torna allo scuro")

print(failures == 0 ? "\nTutti i test passati." : "\n\(failures) test falliti.")
exit(failures == 0 ? 0 : 1)
