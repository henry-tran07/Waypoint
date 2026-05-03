import SwiftUI

struct VoiceControlButton: View {
    @EnvironmentObject var coordinator: VoiceCoordinator

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(ringColor, lineWidth: 2 + CGFloat(coordinator.level) * 6)
                    .frame(width: 88, height: 88)
                    .animation(.easeOut(duration: 0.08), value: coordinator.level)

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
            .onTapGesture {
                if coordinator.status.isError {
                    coordinator.openSettings()
                } else {
                    coordinator.toggle()
                }
            }

            Text(captionText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .frame(height: 14)
        }
    }

    private var iconName: String {
        switch coordinator.status {
        case .live: return "waveform"
        case .connecting, .requestingPermission: return "mic"
        case .error: return "exclamationmark.triangle.fill"
        case .offline, .off: return "mic.fill"
        }
    }

    private var iconColor: Color {
        switch coordinator.status {
        case .live: return .green
        case .error: return .red
        default: return .white
        }
    }

    private var ringColor: Color {
        switch coordinator.status {
        case .live: return .green
        case .connecting, .requestingPermission: return .yellow
        case .error: return .red
        case .offline: return .orange
        case .off: return .white.opacity(0.25)
        }
    }

    private var captionText: String {
        switch coordinator.status {
        case .off: return "Tap to talk"
        case .requestingPermission: return "Permission…"
        case .connecting: return "Connecting…"
        case .live: return "Listening"
        case .offline: return "Offline"
        case .error: return "Tap for Settings"
        }
    }
}
