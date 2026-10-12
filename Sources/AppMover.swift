import Cocoa

/// If WorkHub is opened outside Applications (from the DMG, Downloads, the build folder),
/// offers to move it to /Applications and relaunches from there, as downloaded apps do.
enum AppMover {
    private static let skipKey = "skipMoveToApplications"

    /// Returns true if the app is relaunching from /Applications (in that case, don't initialize it).
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
                try fileManager.trashItem(at: destination, resultingItemURL: nil)   // previous version to the Trash
            }
            try fileManager.copyItem(at: current, to: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't move WorkHub"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag it to the Applications folder in the Finder."
            _ = failure.runModal()
            return false
        }

        // Reopens the copy in Applications as soon as this instance has quit.
        let pid = ProcessInfo.processInfo.processIdentifier
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", destination.path]
        try? relaunch.run()

        // The old copy goes to the Trash (not possible from the DMG: it's read-only, and that's fine).
        try? fileManager.trashItem(at: current, resultingItemURL: nil)
        NSApp.terminate(nil)
        return true
    }
}
