import SwiftUI

@main
struct MiraApp: App {
    @StateObject private var store = SceneStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
    }
}
