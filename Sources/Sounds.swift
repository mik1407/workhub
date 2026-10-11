import Foundation
import AVFoundation

/// Suoni di sottofondo del Focus: i file audio in ~/Library/Application Support/WorkHub/Sounds/.
/// Non sono dentro l'app (e quindi nemmeno nel DMG): restano sul tuo Mac.
enum SoundLibrary {
    struct Sound {
        let id: String      // nome del file
        let name: String    // nome mostrato
        let url: URL
    }

    static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aif", "aiff", "aac"]

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkHub/Sounds", isDirectory: true)
    }

    static func all() -> [Sound] {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map { Sound(id: $0.lastPathComponent, name: displayName(for: $0), url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Copia i file scelti nella cartella dei suoni; restituisce gli id aggiunti.
    static func add(_ urls: [URL]) -> [String] {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var added: [String] = []
        for url in urls where audioExtensions.contains(url.pathExtension.lowercased()) {
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            if destination.standardizedFileURL == url.standardizedFileURL { continue }
            try? fileManager.removeItem(at: destination)
            if (try? fileManager.copyItem(at: url, to: destination)) != nil { added.append(url.lastPathComponent) }
        }
        return added
    }

    /// "bgm_WindWithCrickets.m4a" → "Wind With Crickets"
    static func displayName(for url: URL) -> String {
        var base = url.deletingPathExtension().lastPathComponent
        for prefix in ["bgm_", "alm_"] where base.hasPrefix(prefix) { base.removeFirst(prefix.count) }
        var result = ""
        var previous: Character?
        for character in base {
            if character == "_" || character == "-" {
                result.append(" ")
                previous = " "
                continue
            }
            if let p = previous, character.isUppercase, p.isLowercase { result.append(" ") }
            result.append(character)
            previous = character
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// Riproduce un suono in loop continuo.
/// - volume livellato tra i suoni (stessa intensità percepita);
/// - giunzione del loop con dissolvenza incrociata (nessuno stacco alla ripetizione);
/// - cambio suono con dissolvenza; in memoria resta solo il suono in uso (massimo ~60 s).
final class AmbientPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private var connectedFormat: AVAudioFormat?
    private var cached: (url: URL, buffer: AVAudioPCMBuffer)?
    private var currentURL: URL?
    private var playing = false
    private var request = 0
    private var fadeTimer: Timer?
    private var fadeFrom: Float = 0
    private var fadeTo: Float = 0
    private var fadeStep = 0
    private var fadeSteps = 1
    private var fadeCompletion: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        // Cambio di uscita audio (cuffie, AirPods): il motore si ferma e va riavviato.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: engine, queue: .main) { [weak self] _ in
            self?.restartAfterDeviceChange()
        }
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Avvia il suono, o passa a un altro con una breve dissolvenza.
    func play(url: URL, volume: Float) {
        if playing && currentURL == url && player.isPlaying {
            fade(to: volume, over: 0.8, then: nil)
            return
        }
        playing = true
        request += 1
        let token = request
        load(url) { [weak self] buffer in
            guard let self = self, self.request == token, self.playing, let buffer = buffer else { return }
            if self.player.isPlaying {
                self.fade(to: 0, over: 0.35) { [weak self] in self?.start(buffer, url: url, volume: volume, token: token) }
            } else {
                self.start(buffer, url: url, volume: volume, token: token)
            }
        }
    }

    func stop() {
        guard playing else { return }
        playing = false
        request += 1
        fade(to: 0, over: 1.2) { [weak self] in
            guard let self = self, !self.playing else { return }
            self.player.stop()
            self.engine.stop()
            self.currentURL = nil
        }
    }

    func setVolume(_ volume: Float) {
        guard playing, player.isPlaying else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadeCompletion = nil
        player.volume = volume
    }

    // MARK: - Riproduzione

    private func start(_ buffer: AVAudioPCMBuffer, url: URL, volume: Float, token: Int) {
        guard playing, request == token else { return }
        player.stop()
        if !attached {
            engine.attach(player)
            attached = true
        }
        if connectedFormat != buffer.format {
            guard connectPlayer(format: buffer.format) else { playing = false; return }
            connectedFormat = buffer.format
        }
        if !engine.isRunning {
            guard (try? engine.start()) != nil else { playing = false; return }
        }
        currentURL = url
        player.volume = 0
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        guard startPlayer() else { playing = false; return }
        fade(to: volume, over: 1.5, then: nil)
    }

    // Da macOS 27 le API segnalano gli errori; prima si usano quelle precedenti (l'app parte da macOS 12).
    private func connectPlayer(format: AVAudioFormat) -> Bool {
        if #available(macOS 27.0, *) {
            return (try? engine.connectNode(player, to: engine.mainMixerNode, format: format)) != nil
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        return true
    }

    private func startPlayer() -> Bool {
        if #available(macOS 27.0, *) {
            return (try? player.playAudio()) != nil
        }
        player.play()
        return true
    }

    private func load(_ url: URL, completion: @escaping (AVAudioPCMBuffer?) -> Void) {
        if let cached = cached, cached.url == url {
            completion(cached.buffer)
            return
        }
        // Decodifica fuori dal thread principale: l'interfaccia non si blocca.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = AmbientPlayer.decodeLoop(url)
            DispatchQueue.main.async {
                if let buffer = buffer { self?.cached = (url, buffer) }
                completion(buffer)
            }
        }
    }

    private func restartAfterDeviceChange() {
        guard playing, let url = currentURL, let cached = cached, cached.url == url else { return }
        guard connectPlayer(format: cached.buffer.format) else { return }
        connectedFormat = cached.buffer.format
        guard (try? engine.start()) != nil else { return }
        player.scheduleBuffer(cached.buffer, at: nil, options: .loops, completionHandler: nil)
        _ = startPlayer()
    }

    // MARK: - Preparazione del loop

    private static let maxSeconds = 60.0
    private static let crossfadeSeconds = 1.5
    private static let targetRMS: Float = 0.0398   // circa -28 dBFS

    /// Legge al massimo ~60 s del file, livella il volume e unisce fine e inizio con una dissolvenza.
    /// I suoni con i bordi silenziosi (es. ticchettio) restano intatti: il loop è già pulito
    /// e una dissolvenza ne sovrapporrebbe il ritmo.
    static func decodeLoop(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let maxFrames = AVAudioFrameCount(min(Double(file.length), sampleRate * (maxSeconds + crossfadeSeconds)))
        guard maxFrames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames),
              (try? file.read(into: input, frameCount: maxFrames)) != nil,
              let source = input.floatChannelData else { return nil }

        let channels = Int(format.channelCount)
        let n = Int(input.frameLength)
        guard n > 0 else { return nil }

        // Livello: RMS e picco su tutti i canali
        var sumSquares: Double = 0
        var peak: Float = 0
        for ch in 0..<channels {
            let samples = source[ch]
            for i in 0..<n {
                let v = samples[i]
                sumSquares += Double(v * v)
                peak = max(peak, abs(v))
            }
        }
        let rms = Float((sumSquares / Double(n * channels)).squareRoot())
        var gain = targetRMS / max(rms, 0.000_001)
        if peak > 0 { gain = min(gain, 0.95 / peak) }

        // Bordi silenziosi? (sotto -60 dB nei primi e negli ultimi 50 ms)
        let edge = max(1, min(n / 4, Int(sampleRate * 0.05)))
        func edgeRMS(from start: Int) -> Float {
            var sum: Float = 0
            for ch in 0..<channels {
                for i in start..<(start + edge) { sum += source[ch][i] * source[ch][i] }
            }
            return (sum / Float(edge * channels)).squareRoot()
        }
        let silentEdges = edgeRMS(from: 0) < 0.001 && edgeRMS(from: n - edge) < 0.001
        let fade = (silentEdges || n < Int(sampleRate * 2)) ? 0 : min(Int(sampleRate * crossfadeSeconds), n / 6)

        let length = n - fade
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
              let destination = output.floatChannelData else { return nil }
        output.frameLength = AVAudioFrameCount(length)
        for ch in 0..<channels {
            let s = source[ch], d = destination[ch]
            for i in 0..<length {
                var v = s[i]
                if i < fade {
                    // Dissolvenza a potenza costante: l'inizio entra mentre la coda (gli ultimi secondi) esce.
                    let t = Float(i) / Float(fade) * Float.pi / 2
                    v = s[i] * sin(t) + s[n - fade + i] * cos(t)
                }
                d[i] = v * gain
            }
        }
        return output
    }

    // MARK: - Dissolvenze

    private func fade(to target: Float, over seconds: TimeInterval, then completion: (() -> Void)?) {
        fadeTimer?.invalidate()
        fadeFrom = player.volume
        fadeTo = target
        fadeStep = 0
        fadeSteps = max(1, Int(seconds / 0.05))
        fadeCompletion = completion
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.fadeTick() }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func fadeTick() {
        fadeStep += 1
        let x = Float(fadeStep) / Float(fadeSteps)
        let eased = x * x * (3 - 2 * x)
        player.volume = fadeFrom + (fadeTo - fadeFrom) * eased
        if fadeStep >= fadeSteps {
            fadeTimer?.invalidate()
            fadeTimer = nil
            let completion = fadeCompletion
            fadeCompletion = nil
            completion?()
        }
    }
}
