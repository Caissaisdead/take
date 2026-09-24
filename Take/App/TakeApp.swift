import SwiftUI

@main
struct TakeApp: App {
    @State private var model = ProjectModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Take") {
                Button("New Take…") { model.isNamingTake = true }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(model.selection == nil)
                Divider()
                Button("Keep Take") { model.keep() }
                    .disabled(!model.isInTake)
            }
        }
    }
}
