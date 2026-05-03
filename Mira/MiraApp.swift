import SwiftUI

@main
struct MiraApp: App {
    @StateObject private var store = SceneStore()
    @StateObject private var speech = SpeechService()
    @StateObject private var tts = TTSService()
    @StateObject private var coordinator = VoiceCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(speech)
                .environmentObject(tts)
                .environmentObject(coordinator)
                .onAppear {
                    coordinator.bind(store: store, speech: speech, tts: tts)
                }
        }
    }
}
