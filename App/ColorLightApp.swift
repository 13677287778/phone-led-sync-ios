import SwiftUI

@main struct ColorLightApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.foreground(true) }
                    else if phase == .background { model.foreground(false) }
                }
        }
    }
}
