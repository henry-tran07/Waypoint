import SwiftUI

struct StatusOverlay: View {
    @EnvironmentObject var store: SceneStore

    var body: some View {
        let labels = store.objects.keys.sorted()
        Text(labels.isEmpty ? "Seen: (none)" : "Seen: \(labels.joined(separator: ", "))")
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
