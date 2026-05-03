import SwiftUI
import Combine

struct TranscriptOverlay: View {
    @EnvironmentObject var coordinator: VoiceCoordinator
    @State private var visible: Bool = false
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !coordinator.transcript.isEmpty {
                Text(coordinator.transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            if let last = coordinator.miraResponse, !last.isEmpty {
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
        .onReceive(coordinator.$transcript) { _ in scheduleFade() }
        .onReceive(coordinator.$miraResponse) { _ in scheduleFade() }
    }

    private func scheduleFade() {
        let hasContent = !coordinator.transcript.isEmpty || !(coordinator.miraResponse?.isEmpty ?? true)
        if hasContent { visible = true }
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}
