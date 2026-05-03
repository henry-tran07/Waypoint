import SwiftUI

struct StatusOverlay: View {
    @EnvironmentObject var store: SceneStore

    var body: some View {
        let labels = store.objects.keys.sorted()
        Group {
            if labels.isEmpty {
                emptyState
            } else {
                chips(for: labels)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.7))
            Text("Scanning the room…")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func chips(for labels: [String]) -> some View {
        let visible = Array(labels.prefix(6))
        let extra = labels.count - visible.count
        return HStack(spacing: 6) {
            ForEach(visible, id: \.self) { label in
                Chip(label: label, store: store)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

private struct Chip: View {
    let label: String
    let store: SceneStore
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .scaleEffect(scale)
            .onReceive(store.$lastDetectedLabel) { newLabel in
                if newLabel?.lowercased() == label { pulse() }
            }
    }

    private func pulse() {
        withAnimation(.spring(duration: 0.15, bounce: 0.3)) {
            scale = 1.08
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.spring(duration: 0.15, bounce: 0.3)) {
                scale = 1.0
            }
        }
    }
}
