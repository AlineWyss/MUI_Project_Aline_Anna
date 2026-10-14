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
    /// Welche Stimme für welche erkannte Sprache verwendet wird.
    /// "de-CH" = Schweizer Hochdeutsch. Ist sie auf dem Gerät nicht vorhanden,
    /// wird automatisch "de-DE" genommen.
    var voices: [String: [String]] = [
        "en": ["en-GB", "en-US"],
        "de": ["de-CH", "de-DE"]
    ]

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    private init() {
        // Gesprochenes Audio: auch hörbar, wenn andere Töne laufen
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Spielt einen Clip: zuerst die Audiodatei `clip` (falls vorhanden), sonst wird `text` vorgelesen.
    /// - Parameters:
    ///   - clip: Dateiname OHNE Endung, z. B. "voice_addHemoglobin". nil = immer vorlesen.
    ///   - text: Text für die synthetische Stimme
    func speak(clip: String? = nil, text: String) {
        guard isEnabled else { return }
        stop()   // Alles Laufende sofort abbrechen

        // 1) Gibt es eine Aufnahme?
        if let clip,
           let url = Bundle.main.url(forResource: clip, withExtension: "m4a")
                ?? Bundle.main.url(forResource: clip, withExtension: "mp3")
                ?? Bundle.main.url(forResource: clip, withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
            return
        }

        // 2) Sonst vorlesen
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: text)
        utterance.rate = rate
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    /// true, solange gesprochen oder eine Aufnahme abgespielt wird.
    var isSpeaking: Bool {
        synthesizer.isSpeaking || (player?.isPlaying ?? false)
    }

    /// Bricht die Stimme sofort ab.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        player?.stop()
        player = nil
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
