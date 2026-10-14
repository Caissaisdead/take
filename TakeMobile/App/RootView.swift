import SwiftUI

/// One stack: Projects, then a project's binder, then a scene. Nothing is
/// in it yet but the list's empty state; the screens follow.
struct RootView: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        NavigationStack {
            ContentUnavailableView("No projects yet", systemImage: "books.vertical", description: Text("Pull a draft from a remote to begin."))
                .navigationTitle("Projects")
        }
        .tint(Accent.current.color)
    }
}
