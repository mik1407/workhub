import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.offerIfNeeded() { return }   // si sta riaprendo da /Applications
        // Evita che App Nap rallenti l'app quando è in background (notifiche in ritardo).
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Servizi di messaggistica attivi")
        Notifier.shared.setup()
        let controller = AppController()
        controller.buildMenu()
        controller.start()
        self.controller = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    // Click sull'icona nel Dock con la finestra chiusa → la riapre.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller?.showWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
