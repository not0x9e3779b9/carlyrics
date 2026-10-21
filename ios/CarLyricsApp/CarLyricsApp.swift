import SwiftUI

@main
struct CarLyricsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(.indigo)
                .task {
                    model.setForeground(scenePhase == .active)
                    await model.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in model.setForeground(phase == .active) }
        }
    }
}
