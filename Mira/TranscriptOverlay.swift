import SwiftUI
import Combine

struct TranscriptOverlay: View {
    @EnvironmentObject var speech: SpeechService
    @EnvironmentObject var tts: TTSService
    @State private var visible: Bool = false
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !speech.transcript.isEmpty {
                Text(speech.transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            if let last = tts.lastSpoken, !last.isEmpty {
                Text(last)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .onReceive(speech.$transcript) { _ in scheduleFade() }
        .onReceive(tts.$lastSpoken) { _ in scheduleFade() }
    }

    private func scheduleFade() {
        let hasContent = !speech.transcript.isEmpty || !(tts.lastSpoken?.isEmpty ?? true)
        if hasContent { visible = true }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}
