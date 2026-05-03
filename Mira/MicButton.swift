import SwiftUI

struct MicButton: View {
    @EnvironmentObject var store: SceneStore
    @EnvironmentObject var speech: SpeechService
    @EnvironmentObject var tts: TTSService

    var body: some View {
        let isOn = speech.isListening
        Image(systemName: isOn ? "mic.fill" : "mic")
            .font(.system(size: 36))
            .foregroundStyle(.white)
            .padding(28)
            .background(
                Circle().fill(isOn ? Color.red.opacity(0.85) : Color.black.opacity(0.55))
            )
            .overlay(
                Circle().stroke(isOn ? Color.cyan : Color.white.opacity(0.3), lineWidth: isOn ? 3 : 1)
            )
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !speech.isListening { speech.start() }
                    }
                    .onEnded { _ in
                        speech.stop()
                    }
            )
            .onChange(of: speech.isListening) { _, listening in
                guard !listening, !speech.transcript.isEmpty else { return }
                let transcript = speech.transcript
                QueryHandler(store: store, tts: tts).handle(transcript: transcript)
            }
    }
}
