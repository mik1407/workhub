import Cocoa
import ServiceManagement
import WebKit

/// Menu bar.
extension AppController {
    // MARK: - Menu

    func buildMenu() {
        let main = NSMenu()
        let appName = "WorkHub"

        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        if #available(macOS 13.0, *) {
            let login = appMenu.addItem(withTitle: "Open at Login",
                                        action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            appMenu.addItem(.separator())
        }
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        // Needed for copy/paste inside web pages
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, to: main)

        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Reload", action: #selector(reloadCurrent(_:)), keyEquivalent: "r").target = self
        let reloadAllItem = view.addItem(withTitle: "Reload All Services",
                                         action: #selector(reloadAllServices(_:)), keyEquivalent: "r")
        reloadAllItem.keyEquivalentModifierMask = [.command, .shift]
        reloadAllItem.target = self
        let homeItem = view.addItem(withTitle: "Service Home Page",
                                    action: #selector(goHome(_:)), keyEquivalent: "h")
        homeItem.keyEquivalentModifierMask = [.command, .shift]
        homeItem.target = self
        view.addItem(.separator())
        let todosItem = view.addItem(withTitle: "Todos", action: #selector(toggleTodos(_:)),
                                     keyEquivalent: "t")
        todosItem.target = self
        todosItem.state = openPanel == .todos ? .on : .off
        todoMenuItem = todosItem
        let focusItem = view.addItem(withTitle: "Focus", action: #selector(toggleFocus(_:)), keyEquivalent: "f")
        focusItem.keyEquivalentModifierMask = [.command, .shift]
        focusItem.target = self
        focusItem.state = openPanel == .focus ? .on : .off
        focusMenuItem = focusItem
        let snippetsItem = view.addItem(withTitle: "Snippets", action: #selector(toggleSnippets(_:)), keyEquivalent: "")
        snippetsItem.target = self
        snippetsItem.state = openPanel == .snippets ? .on : .off
        snippetsMenuItem = snippetsItem
        view.addItem(.separator())
        view.addItem(withTitle: "Back", action: #selector(navigateBack(_:)), keyEquivalent: "[").target = self
        view.addItem(withTitle: "Forward", action: #selector(navigateForward(_:)), keyEquivalent: "]").target = self
        addSubmenu(view, to: main)

        let go = NSMenu(title: "Go")
        goMenu = go
        rebuildGoMenu()
        addSubmenu(go, to: main)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(windowMenu, to: main)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    func rebuildGoMenu() {
        guard let go = goMenu else { return }
        go.removeAllItems()
        for (index, service) in services.enumerated() {
            let item = go.addItem(withTitle: service.config.name, action: #selector(selectFromMenu(_:)),
                                  keyEquivalent: index < 9 ? String(index + 1) : "")
            item.tag = index
            item.target = self
        }
    }

    private func addSubmenu(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    /// Login item managed by macOS (System Settings > General > Login Items).
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can change it in System Settings > General > Login Items."
            _ = alert.runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        sender.state = service.status == .enabled ? .on : .off
    }

    @objc private func selectFromMenu(_ sender: NSMenuItem) {
        showWindow()
        select(sender.tag)
    }

    @objc private func reloadCurrent(_ sender: Any?) { _ = current?.webView.reload() }
    @objc private func reloadAllServices(_ sender: Any?) { services.forEach { _ = $0.webView.reload() } }
    @objc private func goHome(_ sender: Any?) { current?.reloadHome() }
    @objc private func navigateBack(_ sender: Any?) { _ = current?.webView.goBack() }
    @objc private func navigateForward(_ sender: Any?) { _ = current?.webView.goForward() }
}
