//
//  VoiceGuide.swift
//  BloodCellJourney
//
//  Created by wyss aline on 14.10.2026.
//

import AVFoundation
import NaturalLanguage

@MainActor
final class VoiceGuide {
    static let shared = VoiceGuide()

    /// Für Tests: false = stumm
    var isEnabled = true
    /// Sprechtempo der synthetischen Stimme (0.0–1.0; 0.5 = normal)
    var rate: Float = 0.47
    /// Kleine Pause zwischen zwei Texten, die direkt nacheinander kommen (Sekunden).
    var gapBetweenClips: Double = 0.4
    /// Welche Stimme für welche erkannte Sprache verwendet wird (nur für die synthetische Stimme).
    var voices: [String: [String]] = [
        "en": ["en-GB", "en-US"],
        "de": ["de-CH", "de-DE"]
    ]

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    /// Name of the recording that is playing right now (nil = none, or the synthetic voice).
    private(set) var currentClip: String?

    /// Warteschlange: Texte, die noch gesprochen werden sollen (der Reihe nach).
    private var queue: [(clip: String?, text: String)] = []
    /// Arbeitet die Warteschlange ab (nil = nichts zu tun).
    private var runner: Task<Void, Never>?
    /// Wird bei stop() erhöht – ein alter, abgebrochener Durchlauf erkennt so, dass er aufhören muss.
    private var generation = 0

    private init() {
        // Gesprochenes Audio: auch hörbar, wenn andere Töne laufen
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Öffentlich

    /// Stellt einen Text in die Warteschlange. Läuft gerade nichts, startet er sofort,
    /// sonst direkt nach dem aktuellen Text. Nichts wird abgeschnitten.
    /// - Parameters:
    ///   - clip: Dateiname OHNE Endung, z. B. "voice_meetCell". nil = immer vorlesen.
    ///   - text: Text für die synthetische Stimme (falls es keine Datei gibt)
    func speak(clip: String? = nil, text: String) {
        guard isEnabled else { return }
        queue.append((clip, text))
        if runner == nil { startRunner() }
    }

    /// true, solange gesprochen wird ODER noch Texte in der Warteschlange warten.
    /// (setPanel wartet darauf, bevor die Aufgabe erscheint bzw. es automatisch weitergeht.)
    var isSpeaking: Bool {
        runner != nil || isPlayingNow
    }
    /// Seconds into the recording `clip`, while exactly that recording is playing; otherwise nil.
    func clipTime(of clip: String) -> TimeInterval? {
        guard currentClip == clip, let player, player.isPlaying else { return nil }
        return player.currentTime
    }
    /// Seconds left in the recording `clip`, while exactly that recording is playing; otherwise nil.
    func clipRemaining(of clip: String) -> TimeInterval? {
        guard currentClip == clip, let player, player.isPlaying else { return nil }
        return max(player.duration - player.currentTime, 0)
    }
    /// Bricht alles sofort ab und leert die Warteschlange (Neustart, Skip, Schliessen).
    func stop() {
        generation += 1
        queue.removeAll()
        runner?.cancel()
        runner = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        player?.stop()
        player = nil
        currentClip = nil
    }
    /// Length of the recording `clip` in seconds (read from the file, without playing it). nil if there is none.
    func clipDuration(_ clip: String) -> TimeInterval? {
        guard let url = audioURL(for: clip), let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return player.duration
    }
    // MARK: - Intern

    private var isPlayingNow: Bool {
        synthesizer.isSpeaking || (player?.isPlaying ?? false)
    }

    /// Spielt die Warteschlange der Reihe nach ab.
    private func startRunner() {
        let myGeneration = generation
        runner = Task { @MainActor in
            while myGeneration == self.generation, !self.queue.isEmpty {
                let item = self.queue.removeFirst()
                self.play(item)

                // kurz warten, bis die Wiedergabe sicher läuft …
                try? await Task.sleep(for: .milliseconds(250))
                // … dann warten, bis sie fertig ist
                while myGeneration == self.generation, self.isPlayingNow {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard myGeneration == self.generation else { return }

                // kleine Pause, falls gleich der nächste Text kommt
                if !self.queue.isEmpty {
                    try? await Task.sleep(for: .seconds(self.gapBetweenClips))
                }
            }
            if myGeneration == self.generation {
                self.runner = nil
            }
        }
    }

    /// Spielt EINEN Text: Audiodatei, falls vorhanden – sonst synthetische Stimme.
    private func play(_ item: (clip: String?, text: String)) {
        if let clip = item.clip, let url = audioURL(for: clip) {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            if player?.play() == true {
                currentClip = clip
                return
            }
            // Datei kaputt → zur Sicherheit vorlesen
        }
        currentClip = nil
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = voice(for: item.text)
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// Sucht die Audiodatei zum Clip-Namen in der App.
    private func audioURL(for clip: String) -> URL? {
        for ext in ["m4a", "mp3", "wav", "mp4"] {
            if let url = Bundle.main.url(forResource: clip, withExtension: ext) { return url }
        }
        return nil
    }

    /// Erkennt die Sprache des Textes und wählt eine passende Stimme.
    private func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
        for code in voices[language] ?? [] {
            if let voice = AVSpeechSynthesisVoice(language: code) { return voice }
        }
        return AVSpeechSynthesisVoice(language: language)
    }
}
