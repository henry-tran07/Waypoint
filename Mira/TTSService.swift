import Foundation
import AVFoundation

@MainActor
final class TTSService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("TTSService: audio session configuration failed: \(error)")
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
