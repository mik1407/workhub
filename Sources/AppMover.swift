import Cocoa

/// Se WorkHub viene aperta fuori da Applicazioni (dal DMG, da Download, dalla cartella di build),
/// propone di spostarla in /Applications e si riapre da lì, come fanno le app scaricate.
enum AppMover {
    private static let skipKey = "skipMoveToApplications"

    /// Restituisce true se l'app si sta riavviando da /Applications (in quel caso non va inizializzata).
    static func offerIfNeeded() -> Bool {
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = current.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        if path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/") { return false }
        if UserDefaults.standard.bool(forKey: skipKey) { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move WorkHub to the Applications folder?"
        alert.informativeText = "You'll find it in Launchpad and Spotlight, and you can keep it in the Dock and open it at login."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: skipKey) }
        guard response == .alertFirstButtonReturn else { return false }

        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(current.lastPathComponent)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.trashItem(at: destination, resultingItemURL: nil)   // versione precedente nel Cestino
            }
            try fileManager.copyItem(at: current, to: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't move WorkHub"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag it to the Applications folder in the Finder."
            _ = failure.runModal()
            return false
        }

        // Riapre la copia in Applicazioni appena questa istanza si è chiusa.
        let pid = ProcessInfo.processInfo.processIdentifier
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", destination.path]
        try? relaunch.run()

        // La vecchia copia va nel Cestino (dal DMG non si può: è in sola lettura, e va bene così).
        try? fileManager.trashItem(at: current, resultingItemURL: nil)
        NSApp.terminate(nil)
        return true
    }
}
