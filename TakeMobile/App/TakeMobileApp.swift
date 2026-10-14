import SwiftUI

@main
struct TakeMobileApp: App {
    @State private var model = ProjectModel()
    @State private var index = ProjectIndex()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(index)
        }
        // The idle save waits ten seconds; a trip to the background inside
        // them must not lose the text. Commits take milliseconds.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.saveBeforeLeaving() }
        }
    }
}
