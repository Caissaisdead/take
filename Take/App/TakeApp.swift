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
                Button("New Project…") { model.newProject() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Project…") { model.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open Sample Project") { model.openSample() }
                Divider()
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
            CommandGroup(replacing: .importExport) {
                Menu("Export") {
                    Button("Markdown Folder…") { model.exportMarkdown() }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("Word Document…") { model.exportDocx() }
                        .keyboardShortcut("e", modifiers: [.command, .option])
                }
                .disabled(model.manuscript.scenes.isEmpty)
            }
            CommandMenu("Draft") {
                Button("Find in Draft…") { NotificationCenter.default.post(name: .showFind, object: nil) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(model.manuscript.scenes.isEmpty)
                Divider()
                Button("Untangle This Scene") { NotificationCenter.default.post(name: .showUntangle, object: nil) }
                    .keyboardShortcut("u", modifiers: .command)
                    .disabled(model.selection == nil)
                Button("Three Takes…") { model.requestThreeTakes() }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                    .disabled(model.selection == nil || model.isWritingTakes)
                Button("Mark Milestone…") { model.naming = .milestone }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .disabled(model.manuscript.scenes.isEmpty)
                Divider()
                Button("Reveal in Finder") { model.revealInFinder() }
                Button("Open in Terminal") { model.openInTerminal() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
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
        Settings {
            SettingsView()
        }
    }
}
