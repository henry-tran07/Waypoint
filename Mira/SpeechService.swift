import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechService: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var level: Float = 0

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    func start() {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            print("SpeechService: recognizer unavailable for en-US")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                print("SpeechService: speech auth denied (\(status.rawValue))")
                Task { @MainActor in self.isListening = false }
                return
            }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else {
                    print("SpeechService: mic permission denied")
                    Task { @MainActor in self.isListening = false }
                    return
                }
                Task { @MainActor in self.beginSession() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        silenceTask?.cancel()
        silenceTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isListening = false
        level = 0
    }

    private func beginSession() {
        guard !isListening, let recognizer else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("SpeechService: audio session error \(error)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let lvl = SpeechService.computeLevel(buffer: buffer)
            Task { @MainActor in self?.level = lvl }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("SpeechService: engine start failed \(error)")
            stop()
            return
        }

        transcript = ""
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcript = text
                    self.resetSilenceTimer()
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.stop() }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.stop()
        }
    }

    private static func computeLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let samples = channelData[0]
        var sumSq: Float = 0
        for i in 0..<frameCount { sumSq += samples[i] * samples[i] }
        let rms = (sumSq / Float(frameCount)).squareRoot()
        return min(1.0, rms * 8)
    }
}
