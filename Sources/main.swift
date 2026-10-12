import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.offerIfNeeded() { return }   // relaunching from /Applications
        // Keeps App Nap from slowing the app in the background (late notifications).
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Messaging services running")
        Notifier.shared.setup()
        Theme.apply(SettingsStore.shared.settings.appearance)   // before creating the window and panels
        let controller = AppController()
        controller.buildMenu()
        controller.start()
        self.controller = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    // Clicking the Dock icon with the window closed → reopens it.
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
