import Foundation
import Combine
import Speech
import AVFoundation
import UIKit

@MainActor
final class VoiceCoordinator: ObservableObject {
    enum Status: Equatable {
        case off
        case requestingPermission
        case connecting
        case live
        case offline
        case error(String)

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    @Published private(set) var status: Status = .off
    @Published private(set) var transcript: String = ""
    @Published private(set) var miraResponse: String?
    @Published private(set) var level: Float = 0

    private weak var store: SceneStore?
    private weak var speech: SpeechService?
    private weak var tts: TTSService?
    private var cancellables = Set<AnyCancellable>()

    func bind(store: SceneStore, speech: SpeechService, tts: TTSService) {
        self.store = store
        self.speech = speech
        self.tts = tts

        speech.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.transcript = $0 }
            .store(in: &cancellables)
        speech.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)
        tts.$lastSpoken
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.miraResponse = $0 }
            .store(in: &cancellables)
        speech.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] listening in
                self?.handleListeningChange(listening: listening)
            }
            .store(in: &cancellables)
    }

    var isActive: Bool {
        switch status {
        case .live, .connecting, .requestingPermission: return true
        case .off, .offline, .error: return false
        }
    }

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard speech != nil else { status = .error("not bound"); return }

        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        let micAuth = AVAudioApplication.shared.recordPermission

        if speechAuth == .notDetermined || micAuth == .undetermined {
            status = .requestingPermission
            requestPermissionsThenStart()
            return
        }
        if speechAuth != .authorized || micAuth != .granted {
            status = .error("Microphone permission needed")
            return
        }

        startLocalSession()
    }

    func stop() {
        if let speech, speech.isListening {
            speech.stop()
        } else if status != .off {
            status = .off
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // Local fallback path. The Gemini Live integration replaces this with a
    // streaming WebSocket session; falling back here when Live can't open.
    private func startLocalSession() {
        tts?.stop()
        speech?.start()
        status = .live
    }

    private func handleListeningChange(listening: Bool) {
        guard !listening, status == .live else { return }
        if !transcript.isEmpty {
            dispatchLocalQuery()
        }
        status = .off
    }

    private func dispatchLocalQuery() {
        guard let store, let tts else { return }
        QueryHandler(store: store, tts: tts).handle(transcript: transcript)
    }

    private func requestPermissionsThenStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] sStatus in
            Task { @MainActor in
                guard let self else { return }
                guard sStatus == .authorized else {
                    self.status = .error("Speech recognition denied")
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.status = .error("Microphone denied")
                            return
                        }
                        self.startLocalSession()
                    }
                }
            }
        }
    }
}
