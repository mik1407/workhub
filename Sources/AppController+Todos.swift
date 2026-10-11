import Cocoa

/// Pannello Todos: badge dei todo scaduti, promemoria e pulsanti delle notifiche di scadenza.
extension AppController {
    // MARK: - Todo: scadenze e promemoria

    func setupTodos() {
        todoPanel.onSaved = { [weak self] json in self?.todosChanged(json) }
        todosChanged(todoPanel.lastState)
        // Un todo diventa scaduto col passare del tempo: badge ricontrollato ogni 30 secondi
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshOverdueBadge() }
        RunLoop.main.add(timer, forMode: .common)
        overdueTimer = timer
        // Pulsanti della notifica di scadenza
        Notifier.shared.onAction = { [weak self] action, service, id in
            guard service == "todos", let id = id, let self = self else { return }
            switch action {
            case "todo.done": self.todoPanel.apply("done", to: id)
            case "todo.snooze": self.todoPanel.apply("snooze", to: id)
            default: break
            }
        }
    }

    private func todosChanged(_ json: String) {
        refreshOverdueBadge()
        // Riprogramma i promemoria poco dopo l'ultima modifica (non a ogni tasto)
        reminderWork?.cancel()
        let work = DispatchWorkItem { TodoReminders.reschedule(from: json) }
        reminderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func refreshOverdueBadge() {
        let count = TodoReminders.overdueCount(in: todoPanel.lastState)
        todoButton.badgeCount = count
        todoButton.toolTip = count > 0 ? "Todos  ⌘T (\(count) overdue)" : "Todos  ⌘T"
    }
}
