import Foundation
import AVFoundation

/// Ciclo Pomodoro: 25 minuti di focus, 5 di pausa, e si ripete finché non lo fermi.
/// Il tempo si basa sull'orario reale: niente ritardi accumulati, e dopo uno stop del Mac
/// riparte dalla fase giusta.
final class FocusTimer {
    enum Phase: String {
        case idle, focus
        case rest = "break"
        case longRest = "longBreak"

        var isBreak: Bool { self == .rest || self == .longRest }
    }

    /// Durate e comportamento (Impostazioni > Focus).
    private(set) var settings = FocusSettings()
    /// true quando una fase è finita e la successiva aspetta un click (avvio automatico disattivato).
    private(set) var waiting = false

    private(set) var phase: Phase = .idle
    private(set) var isPaused = false
    private(set) var round = 0                 // numero della sessione di focus in corso
    private var phaseEnd = Date()
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    private let ambient = AmbientPlayer()
    private(set) var sounds: [SoundLibrary.Sound] = SoundLibrary.all()
    private var previewing = false
    private var previewEnd: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    /// Chiamato a ogni aggiornamento (circa due volte al secondo mentre il timer gira).
    var onChange: (() -> Void)?
    /// Chiamato quando si passa da focus a pausa o viceversa (per le notifiche).
    var onPhaseChange: ((Phase) -> Void)?

    /// Suono di sottofondo attivo durante il focus.
    var soundEnabled: Bool {
        get { defaults.object(forKey: "focusRain") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "focusRain") }
    }

    /// Suono scelto (se non esiste più, il primo disponibile; di base la pioggia).
    var currentSound: SoundLibrary.Sound? {
        let saved = defaults.string(forKey: "focusSound") ?? "bgm_Rain.m4a"
        return sounds.first { $0.id == saved } ?? sounds.first { $0.id == "bgm_Rain.m4a" } ?? sounds.first
    }

    var volume: Float {
        get { defaults.object(forKey: "focusVolume") as? Float ?? 0.5 }
        set { defaults.set(newValue, forKey: "focusVolume") }
    }

    var remaining: TimeInterval {
        if phase == .idle { return duration(of: .focus) }
        return isPaused ? pausedRemaining : max(0, phaseEnd.timeIntervalSinceNow)
    }

    var duration: TimeInterval { duration(of: phase) }

    /// Sessioni di focus completate oggi (si azzera a mezzanotte).
    var completedToday: Int {
        defaults.string(forKey: "focusDay") == Self.today() ? defaults.integer(forKey: "focusCount") : 0
    }

    // MARK: - Comandi

    /// Nuove impostazioni: valgono dalla prossima fase (quella in corso non cambia).
    func apply(_ newSettings: FocusSettings) {
        settings = newSettings
        onChange?()
    }

    func start() {
        guard phase == .idle else { return }
        round = 1
        begin(.focus, at: Date())
    }

    func togglePause() {
        guard phase != .idle else { return }
        if isPaused {
            phaseEnd = Date().addingTimeInterval(pausedRemaining)
            isPaused = false
            waiting = false
        } else {
            pausedRemaining = remaining
            isPaused = true
        }
        updateSound()
        onChange?()
    }

    /// Passa subito alla fase successiva (una sessione saltata non conta come completata).
    func skip() {
        guard phase != .idle else { return }
        if phase == .focus {
            begin(nextBreak(after: round), at: Date())
        } else {
            round += 1
            begin(.focus, at: Date())
        }
    }

    func stop() {
        phase = .idle
        isPaused = false
        waiting = false
        round = 0
        ticker?.invalidate()
        ticker = nil
        updateSound()
        onChange?()
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        updateSound()
        onChange?()
    }

    /// Sceglie il suono. Se il focus è in corso cambia subito; altrimenti fa sentire un'anteprima di 6 secondi.
    func selectSound(_ id: String) {
        guard let sound = sounds.first(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: "focusSound")
        if isSoundDue || !soundEnabled {
            updateSound()
        } else {
            previewEnd?.cancel()
            previewing = true
            ambient.play(url: sound.url, volume: volume)
            let end = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.previewing = false
                self.updateSound()
                self.onChange?()
            }
            previewEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: end)
        }
        onChange?()
    }

    func reloadSounds() {
        sounds = SoundLibrary.all()
        updateSound()
        onChange?()
    }

    func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
        ambient.setVolume(volume)
        onChange?()
    }

    /// Messaggi dal pannello: {action: "start" | "pause" | "skip" | "stop" | "sound" | "select" | "volume", value}
    func handle(_ body: Any) {
        guard let message = body as? [String: Any], let action = message["action"] as? String else { return }
        switch action {
        case "start":
            if phase == .idle { start() } else { togglePause() }
        case "pause": togglePause()
        case "skip": skip()
        case "stop": stop()
        case "sound": setSoundEnabled(message["value"] as? Bool ?? !soundEnabled)
        case "select":
            if let id = message["value"] as? String { selectSound(id) }
        case "volume":
            if let value = message["value"] as? NSNumber { setVolume(value.floatValue) }
        default: break
        }
    }

    /// Stato per il pannello, in JSON.
    var stateJSON: String {
        let state: [String: Any] = [
            "phase": phase.rawValue,
            "paused": isPaused,
            "remaining": Int(remaining.rounded(.up)),
            "total": Int(phase == .idle ? duration(of: .focus) : duration),
            "waiting": waiting,
            "round": round,
            "today": completedToday,
            "soundOn": soundEnabled,
            "sound": currentSound?.id ?? "",
            "sounds": sounds.map { ["id": $0.id, "name": $0.name] },
            "audible": isSoundDue || previewing,
            "volume": Double(volume),
            "focusMinutes": settings.focusMinutes,
            "breakMinutes": settings.breakMinutes,
            "longBreakMinutes": settings.longBreakMinutes,
            "longBreakEvery": settings.longBreakEvery,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    // MARK: - Meccanica

    private func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .rest: return TimeInterval(settings.breakMinutes * 60)
        case .longRest: return TimeInterval(settings.longBreakMinutes * 60)
        default: return TimeInterval(settings.focusMinutes * 60)
        }
    }

    /// Dopo la sessione numero `session`: pausa lunga ogni N sessioni (se attiva), altrimenti breve.
    private func nextBreak(after session: Int) -> Phase {
        let every = settings.longBreakEvery
        return every > 0 && session > 0 && session % every == 0 ? .longRest : .rest
    }

    private func begin(_ next: Phase, at start: Date) {
        phase = next
        isPaused = false
        waiting = false
        phaseEnd = start.addingTimeInterval(duration(of: next))
        startTicker()
        updateSound()
        onChange?()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard phase != .idle, !isPaused else { return }
        let now = Date()
        guard phaseEnd <= now else {
            onChange?()
            return
        }
        // Fase finita. Con l'avvio automatico si recuperano anche più fasi (Mac in stop);
        // altrimenti si passa alla fase successiva e si aspetta un click.
        var next = phase
        var end = phaseEnd
        var finishedFocus = 0
        var nextRound = round
        repeat {
            if next == .focus {
                finishedFocus += 1
                next = nextBreak(after: nextRound)
            } else {
                nextRound += 1
                next = .focus
            }
            end = end.addingTimeInterval(duration(of: next))
        } while settings.autoStart && end <= now
        addCompleted(finishedFocus)
        round = nextRound
        phase = next
        if settings.autoStart {
            phaseEnd = end
        } else {
            isPaused = true
            pausedRemaining = duration(of: next)
            waiting = true
        }
        updateSound()
        onPhaseChange?(next)
        onChange?()
    }

    /// true quando il suono deve suonare: focus in corso, non in pausa, suono attivo.
    private var isSoundDue: Bool { phase == .focus && !isPaused && soundEnabled && currentSound != nil }

    private func updateSound() {
        previewEnd?.cancel()
        previewEnd = nil
        previewing = false
        if isSoundDue, let sound = currentSound {
            ambient.play(url: sound.url, volume: volume)
        } else {
            ambient.stop()
        }
    }

    private func addCompleted(_ count: Int) {
        guard count > 0 else { return }
        defaults.set(completedToday + count, forKey: "focusCount")
        defaults.set(Self.today(), forKey: "focusDay")
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
