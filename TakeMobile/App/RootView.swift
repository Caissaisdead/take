import SwiftUI

/// Where the stack can go from Projects.
enum Route: Hashable {
    case project(UUID)
}

/// One stack: Projects, then a project's binder, then a scene. Opens on the
/// project that was open last, else on the list.
struct RootView: View {
    @Environment(ProjectModel.self) private var model
    @Environment(ProjectIndex.self) private var index
    @State private var path: [Route] = []
    @State private var started = false

    var body: some View {
        NavigationStack(path: $path) {
            ProjectsView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .project(let id):
                        ProjectScreen(id: id, path: $path)
                    }
                }
        }
        .tint(Accent.current.color)
        .onAppear(perform: start)
        .onChange(of: model.totalWords) { index.note(model) }
        .onChange(of: model.lastBackup) { index.note(model) }
        .onChange(of: model.lastPull) { index.note(model) }
    }

    private func start() {
        guard !started else { return }
        started = true
        index.load()
        index.seedSampleIfNeeded(into: model)
        if let url = ProjectModel.lastProjectURL(), let id = UUID(uuidString: url.lastPathComponent), index.entry(id) != nil {
            model.open(url)
            if model.projectURL == url { path = [.project(id)] }
        }
    }
}

/// Stands in for the binder until it is built: the project's name, its
/// counts and the status line.
struct ProjectScreen: View {
    @Environment(ProjectModel.self) private var model
    let id: UUID
    @Binding var path: [Route]

    var body: some View {
        List {
            Section {
                LabeledContent("Words", value: model.totalWords.formatted())
                LabeledContent("Chapters", value: "\(model.manuscript.chapters.count)")
                LabeledContent("Scenes", value: "\(model.manuscript.scenes.count)")
            }
            if !model.statusLine.isEmpty {
                Section { Text(model.statusLine).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(model.projectName)
    }
}
