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
        alert.messageText = "Spostare WorkHub nella cartella Applicazioni?"
        alert.informativeText = "Così la trovi in Launchpad e Spotlight, puoi tenerla nel Dock e aprirla all'avvio del Mac."
        alert.addButton(withTitle: "Sposta in Applicazioni")
        alert.addButton(withTitle: "Non ora")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Non chiedere più"
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
            failure.messageText = "Non riesco a spostare WorkHub"
            failure.informativeText = "\(error.localizedDescription)\n\nTrascinala a mano nella cartella Applicazioni dal Finder."
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
