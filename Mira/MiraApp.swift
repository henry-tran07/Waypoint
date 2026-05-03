import SwiftUI

@main
struct MiraApp: App {
    @StateObject private var store = SceneStore()
    @StateObject private var speech = SpeechService()
    @StateObject private var tts = TTSService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(speech)
                .environmentObject(tts)
        }
    }
}
