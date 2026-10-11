import Cocoa
import UniformTypeIdentifiers

/// Focus (Pomodoro): pannello, notifiche di fine fase, suoni.
extension AppController {
    // MARK: - Focus (Pomodoro)

    func setupFocus() {
        focusPanel.onMessage = { [weak self] body in
            guard let self = self else { return }
            switch (body as? [String: Any])?["action"] as? String {
            case "addSounds"?: self.addSounds()
            case "showSounds"?: NSWorkspace.shared.open(SoundLibrary.folder)
            default: self.focusTimer.handle(body)
            }
        }
        focusPanel.onLoad = { [weak self] in self?.focusChanged() }
        focusTimer.onChange = { [weak self] in self?.focusChanged() }
        focusTimer.onPhaseChange = { [weak self] phase in
            guard let self = self else { return }
            let settings = self.focusTimer.settings
            let title: String
            switch phase {
            case .longRest: title = "Long break: \(settings.longBreakMinutes) minutes"
            case .rest: title = "Break: \(settings.breakMinutes) minutes"
            default: title = "Focus: \(settings.focusMinutes) minutes"
            }
            let body: String
            if self.focusTimer.waiting {
                body = phase.isBreak ? "Session done. Start the break when you're ready." : "Break over. Start focus when you're ready."
            } else {
                body = phase.isBreak ? "Step away from the screen." : "Pick one thing and work on it."
            }
            if settings.chime { _ = NSSound(named: "Glass")?.play() }   // con il suono di fine fase la notifica resta muta
            Notifier.shared.show(identifier: "focus-phase", serviceId: "focus", serviceName: "Focus", jsId: nil,
                                 title: title, body: body, silent: settings.chime)
        }
    }

    /// Aggiunge suoni scelti dal Finder alla cartella dei suoni e seleziona il primo.
    private func addSounds() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose sounds to use during focus"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self = self else { return }
            let added = SoundLibrary.add(panel.urls)
            self.focusTimer.reloadSounds()
            if let first = added.first { self.focusTimer.selectSound(first) }
        }
    }

    /// Aggiorna anello e tooltip del pulsante Focus e lo stato mostrato nel pannello.
    func focusChanged() {
        let timer = focusTimer
        if timer.phase == .idle {
            focusButton.progress = nil
            focusButton.toolTip = "Focus  ⌘⇧F"
        } else {
            let left = Int(timer.remaining.rounded(.up))
            let label = timer.phase == .focus ? "Focus" : (timer.phase == .longRest ? "Long break" : "Break")
            focusButton.progress = CGFloat(1 - timer.remaining / max(timer.duration, 1))
            focusButton.progressColor = timer.phase == .focus ? Theme.todoAccent : Theme.breakGreen
            focusButton.progressDimmed = timer.isPaused
            focusButton.toolTip = timer.waiting
                ? "\(label) ready: click to start"
                : String(format: "%@ %ld:%02ld%@", label, left / 60, left % 60, timer.isPaused ? " (paused)" : "")
        }
        focusPanel.run("window.focusUpdate && window.focusUpdate(\(timer.stateJSON))")
    }
}
