import Cocoa

/// Todos panel: overdue todo badge, reminders and due-date notification buttons.
extension AppController {
    // MARK: - Todo: due dates and reminders

    /// Slack links from the todos open in WorkHub's Slack service; any other link goes to the browser.
    func openInSlack(_ url: URL) -> Bool {
        guard baseDomain(url.host) == "slack.com",
              let slack = services.first(where: { baseDomain($0.config.url.host) == "slack.com" }) else { return false }
        show(service: slack)
        slack.open(url)
        return true
    }

    func setupTodos() {
        todoPanel.onSaved = { [weak self] json in self?.todosChanged(json) }
        todoPanel.onOpenLink = { [weak self] url in self?.openInSlack(url) ?? false }
        todosChanged(todoPanel.lastState)
        // A todo becomes overdue as time passes: badge rechecked every 30 seconds
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refreshOverdueBadge() }
        RunLoop.main.add(timer, forMode: .common)
        overdueTimer = timer
        // Due-date notification buttons
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
        // Reschedule reminders shortly after the last change (not on every keystroke)
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
