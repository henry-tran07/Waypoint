import Foundation
import AVFoundation
import AudioToolbox

@MainActor
final class TTSService: ObservableObject {
    @Published private(set) var lastSpoken: String?

    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = TTSService.bestEnglishVoice()

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        lastSpoken = trimmed

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("TTSService: audio session configuration failed: \(error)")
        }

        AudioServicesPlaySystemSound(1057)

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}
