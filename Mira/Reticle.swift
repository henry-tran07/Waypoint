import SwiftUI

struct Reticle: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color.cyan)
                .frame(width: 4, height: 4)
        }
        .accessibilityHidden(true)
    }
}
