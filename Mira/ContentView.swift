import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SceneStore
    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()

            Reticle()

            VStack(spacing: 0) {
                TranscriptOverlay()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    StatusOverlay()
                    Spacer(minLength: 12)
                    VoiceControlButton()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}
