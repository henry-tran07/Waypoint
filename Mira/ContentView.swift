import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: SceneStore
    var body: some View {
        ZStack {
            ARViewContainer().ignoresSafeArea()
            VStack {
                StatusOverlay().padding(.top, 50)
                Spacer()
                MicButton().padding(.bottom, 50)
            }
        }
    }
}
