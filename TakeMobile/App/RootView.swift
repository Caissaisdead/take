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
                        EditorScreen()
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
        if let pose = ProjectModel.shotPose {
            self.pose(pose)
            return
        }
        if let url = ProjectModel.lastProjectURL(), let id = UUID(uuidString: url.lastPathComponent), index.entry(id) != nil {
            model.open(url)
            if model.projectURL == url { path = [.project(id)] }
        }
    }

    /// With `-TakeShot <pose>` on the command line the app opens the sample
    /// and poses for a store screenshot: `projects`, `binder`, `scene` or
    /// `take`. Nothing is saved.
    private func pose(_ pose: String) {
        guard let sample = index.entries.first(where: { $0.title == "Sample Project" }) ?? index.entries.first else { return }
        model.open(sample.folder)
        guard model.projectURL == sample.folder else { return }
        switch pose {
        case "projects":
            path = []
        case "binder":
            path = [.project(sample.id)]
        case "scene", "take":
            guard let scene = model.manuscript.scenes.first else { return }
            model.select(.main(scene.id))
            if pose == "take", let take = model.takes.first { model.select(.take(take)) }
            path = [.project(sample.id), .scene(scene.id)]
        default:
            path = [.project(sample.id)]
        }
    }
}
