import SwiftUI
import ManuscriptKit

/// Where the stack can go from Projects.
enum Route: Hashable {
    case project(UUID)
    case scene(SceneID)
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
                    case .project:
                        MobileBinderView(path: $path)
                    case .scene:
                        SceneScreen()
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

/// Stands in for the editor until it is built: the scene's text, read only.
struct SceneScreen: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        ScrollView {
            Text(model.editorText)
                .font(.system(size: 18, design: .serif))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .navigationTitle(model.sceneTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
