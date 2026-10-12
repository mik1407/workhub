import Foundation
import AVFoundation

/// Pomodoro cycle: 25 minutes of focus, 5 of break, repeating until you stop it.
/// Timing is based on the real clock: no accumulated drift, and after the Mac sleeps
/// it resumes in the right phase.
final class FocusTimer {
    enum Phase: String {
        case idle, focus
        case rest = "break"
        case longRest = "longBreak"

        var isBreak: Bool { self == .rest || self == .longRest }
    }

    /// Durations and behavior (Settings > Focus).
    private(set) var settings = FocusSettings()
    /// true when a phase has ended and the next one is waiting for a click (auto-start off).
    private(set) var waiting = false

    private(set) var phase: Phase = .idle
    private(set) var isPaused = false
    private(set) var round = 0                 // number of the current focus session
    private var phaseEnd = Date()
    private var pausedRemaining: TimeInterval = 0
    private var ticker: Timer?
    private let ambient = AmbientPlayer()
    private(set) var sounds: [SoundLibrary.Sound] = SoundLibrary.all()
    private var previewing = false
    private var previewEnd: DispatchWorkItem?
    private let defaults = UserDefaults.standard

    /// Called on every update (about twice a second while the timer runs).
    var onChange: (() -> Void)?
    /// Called when switching from focus to break or vice versa (for notifications).
    var onPhaseChange: ((Phase) -> Void)?

    /// Background sound enabled during focus.
    var soundEnabled: Bool {
        get { defaults.object(forKey: "focusRain") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "focusRain") }
    }

    /// Chosen sound (if it no longer exists, the first available; rain by default).
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

    /// Focus sessions completed today (resets at midnight).
    var completedToday: Int {
        defaults.string(forKey: "focusDay") == Self.today() ? defaults.integer(forKey: "focusCount") : 0
    }

    // MARK: - Commands

    /// New settings: they apply from the next phase (the current one does not change).
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

    /// Moves straight to the next phase (a skipped session does not count as completed).
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

    /// Picks the sound. If focus is running it switches right away; otherwise it plays a 6-second preview.
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

    /// Messages from the panel: {action: "start" | "pause" | "skip" | "stop" | "sound" | "select" | "volume", value}
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

    /// State for the panel, as JSON.
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

    // MARK: - Mechanics

    private func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .rest: return TimeInterval(settings.breakMinutes * 60)
        case .longRest: return TimeInterval(settings.longBreakMinutes * 60)
        default: return TimeInterval(settings.focusMinutes * 60)
        }
    }

    /// After session number `session`: a long break every N sessions (if enabled), otherwise a short one.
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
        // Phase over. With auto-start, several phases may be caught up (Mac asleep);
        // otherwise move to the next phase and wait for a click.
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

    /// true when the sound should play: focus running, not paused, sound enabled.
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
