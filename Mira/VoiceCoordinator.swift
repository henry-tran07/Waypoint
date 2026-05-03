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

    private var live: GeminiLiveService?
    private var modeCancellables = Set<AnyCancellable>()

    func bind(store: SceneStore, speech: SpeechService, tts: TTSService) {
        self.store = store
        self.speech = speech
        self.tts = tts
    }

    var isActive: Bool {
        switch status {
        case .live, .connecting, .requestingPermission: return true
        case .off, .offline, .error: return false
        }
    }

    // MARK: - Public

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

        startBestAvailable()
    }

    func stop() {
        if let live {
            live.stop()
        }
        live = nil
        if let speech, speech.isListening {
            speech.stop()
        }
        modeCancellables.removeAll()
        if status != .off {
            status = .off
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Mode selection

    private func startBestAvailable() {
        if !geminiAPIKey.isEmpty {
            startLive()
        } else {
            startLocalSession()
        }
    }

    private func startLive() {
        guard let store else { return }
        modeCancellables.removeAll()
        transcript = ""
        miraResponse = nil
        level = 0

        let liveService = GeminiLiveService(apiKey: geminiAPIKey, store: store)
        self.live = liveService

        liveService.$userTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] t in self?.transcript = t }
            .store(in: &modeCancellables)
        liveService.$miraTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] t in
                guard !t.isEmpty else { return }
                self?.miraResponse = t
            }
            .store(in: &modeCancellables)
        liveService.$inputLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] l in self?.level = l }
            .store(in: &modeCancellables)
        liveService.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] s in self?.handleLiveStatus(s) }
            .store(in: &modeCancellables)

        status = .connecting
        liveService.start()
    }

    private func startLocalSession() {
        guard let speech, let tts else { return }
        modeCancellables.removeAll()
        transcript = ""
        miraResponse = nil
        level = 0

        speech.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.transcript = $0 }
            .store(in: &modeCancellables)
        speech.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &modeCancellables)
        tts.$lastSpoken
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.miraResponse = $0 }
            .store(in: &modeCancellables)
        speech.$isListening
            .receive(on: RunLoop.main)
            .sink { [weak self] listening in
                self?.handleLocalListeningChange(listening: listening)
            }
            .store(in: &modeCancellables)

        tts.stop()
        speech.start()
        status = .live
    }

    // MARK: - Mode handlers

    private func handleLiveStatus(_ liveStatus: GeminiLiveService.Status) {
        switch liveStatus {
        case .connecting:
            status = .connecting
        case .live:
            status = .live
        case .disconnected:
            if status == .live || status == .connecting {
                status = .off
            }
        case .error:
            // Live failed mid-session. Drop to offline; user can re-tap to try again
            // (will use local fallback automatically since Live is now nil).
            live = nil
            modeCancellables.removeAll()
            status = .offline
        }
    }

    private func handleLocalListeningChange(listening: Bool) {
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

    // MARK: - Permissions

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
                        self.startBestAvailable()
                    }
                }
            }
        }
    }
}
