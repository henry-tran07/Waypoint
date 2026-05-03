import SwiftUI

struct VoiceControlButton: View {
    @EnvironmentObject var store: SceneStore
    @EnvironmentObject var speech: SpeechService
    @EnvironmentObject var tts: TTSService

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: 2 + CGFloat(speech.level) * 6)
                    .frame(width: 88, height: 88)
                    .animation(.easeOut(duration: 0.08), value: speech.level)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    )

                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .contentShape(Circle())
            .onTapGesture { toggle() }
            .onChange(of: speech.isListening) { _, listening in
                guard !listening, !speech.transcript.isEmpty else { return }
                let transcript = speech.transcript
                QueryHandler(store: store, tts: tts).handle(transcript: transcript)
            }

            Text(captionText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(height: 14)
        }
    }

    private var iconName: String {
        speech.isListening ? "waveform" : "mic.fill"
    }

    private var iconColor: Color {
        speech.isListening ? .green : .white
    }

    private var ringColor: Color {
        speech.isListening ? .green : .white.opacity(0.25)
    }

    private var captionText: String {
        speech.isListening ? "Listening" : "Tap to talk"
    }

    private func toggle() {
        if speech.isListening {
            speech.stop()
        } else {
            tts.stop()
            speech.start()
        }
    }
}
