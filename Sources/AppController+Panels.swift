import Cocoa
import WebKit

/// Pannelli a destra (Todos, Focus): apertura, chiusura e animazioni.
extension AppController {
    // MARK: - Pannelli a destra (Todos, Focus)

    @objc func toggleTodos(_ sender: Any?) {
        showWindow()
        setPanel(openPanel == .todos ? nil : .todos, animated: true, focus: true)
    }

    @objc func toggleFocus(_ sender: Any?) {
        showWindow()
        setPanel(openPanel == .focus ? nil : .focus, animated: true, focus: true)
    }

    /// Apre un pannello (o lo cambia se ne è già aperto un altro) oppure chiude con nil.
    func setPanel(_ target: SidePanel?, animated: Bool, focus: Bool) {
        openPanel = target
        todoButton.isActive = target == .todos
        focusButton.isActive = target == .focus
        todoMenuItem?.state = target == .todos ? .on : .off
        focusMenuItem?.state = target == .focus ? .on : .off
        UserDefaults.standard.set(target?.rawValue ?? "", forKey: "openPanel")
        if let target = target {
            // Cambia contenuto; in chiusura resta visibile quello attuale mentre scorre via.
            todoPanel.webView.isHidden = target != .todos
            focusPanel.webView.isHidden = target != .focus
            if target == .focus { focusPanel.run("window.focusUpdate && window.focusUpdate(\(focusTimer.stateJSON))") }
        }
        panelTransition += 1
        let token = panelTransition
        let panel = panelContainer
        let width = LocalPanel.width
        let contentInset = width + Self.cardGap

        if !animated {
            panel.isHidden = target == nil
            panelLeading.constant = target == nil ? 0 : -width
            contentTrailing.constant = target == nil ? 0 : -contentInset
            return
        }

        if let target = target {
            // 1. il pannello entra scorrendo sopra il servizio (se è già aperto, cambia solo contenuto)
            // 2. poi il servizio si restringe dietro il pannello (il ridisegno resta coperto)
            panel.isHidden = false
            slidePanel(to: -width) { [weak self] in
                guard let self = self, self.panelTransition == token else { return }
                self.contentTrailing.constant = -contentInset
            }
            if focus {
                switch target {
                case .todos:
                    _ = window.makeFirstResponder(todoPanel.webView)
                    todoPanel.focusInput()
                case .focus:
                    _ = window.makeFirstResponder(focusPanel.webView)
                }
            }
        } else {
            // 1. il servizio si allarga dietro il pannello
            // 2. quando la pagina ha ridisegnato alla nuova larghezza, il pannello esce scorrendo
            contentTrailing.constant = 0
            window.contentView?.layoutSubtreeIfNeeded()
            afterRepaint(of: current?.webView) { [weak self] in
                guard let self = self, self.panelTransition == token else { return }
                self.slidePanel(to: 0) { [weak self] in
                    guard let self = self, self.panelTransition == token else { return }
                    panel.isHidden = true
                }
            }
            if focus, let web = current?.webView { _ = window.makeFirstResponder(web) }
        }
    }

    private func slidePanel(to constant: CGFloat, completion: @escaping () -> Void) {
        guard let root = window.contentView else { completion(); return }
        root.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.panelLeading.constant = constant
            root.layoutSubtreeIfNeeded()
        }, completionHandler: completion)
    }

    /// Esegue `action` quando la pagina ha disegnato almeno due frame alla nuova dimensione
    /// (con un limite di sicurezza di 0,4 s se la pagina non risponde).
    private func afterRepaint(of webView: WKWebView?, _ action: @escaping () -> Void) {
        var done = false
        let finish = {
            if done { return }
            done = true
            action()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: finish)
        guard let webView = webView else { finish(); return }
        webView.callAsyncJavaScript(
            "await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));",
            arguments: [:], in: nil, in: .defaultClient) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: finish)
        }
    }
}
