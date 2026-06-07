import AVFoundation
import SwiftUI

/// Thin wrapper around `AVSpeechSynthesizer` for on-device Japanese TTS.
/// `currentText` is published so views can show a Stop icon while their own
/// sentence is being read.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    @Published private(set) var currentText: String?

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: String = "ja-JP") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        currentText = trimmed
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentText = nil
    }

    func isSpeaking(_ text: String) -> Bool {
        currentText == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.currentText = nil }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.currentText = nil }
    }
}
