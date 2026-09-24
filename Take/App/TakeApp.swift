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
            CommandGroup(replacing: .newItem) {
                Button("New Scene…") { model.naming = .scene }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Chapter…") { model.naming = .chapter }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("New Part…") { model.naming = .part }
                    .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Draft") {
                Button("Mark Milestone…") { model.naming = .milestone }
                    .keyboardShortcut("m", modifiers: .command)
                    .disabled(model.manuscript.scenes.isEmpty)
            }
            CommandMenu("Take") {
                Button("New Take…") { model.naming = .take }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(model.selection == nil)
                Divider()
                Button("Keep Take") { model.keep() }
                    .disabled(!model.isInTake)
            }
        }
    }
}
