import SwiftUI
import ManuscriptKit

/// The Scene pane: the synopsis and the writer's notes on the open scene,
/// kept in the manifest. Saved two seconds after the last keystroke and when
/// the pane goes away, never on every key: each save is a commit.
struct SceneView: View {
    @Environment(ProjectModel.self) private var model
    @State private var synopsis = ""
    @State private var notes = ""
    @State private var loadedFor: SceneID?
    @State private var pending: Task<Void, Never>?

    var body: some View {
        if let scene = model.currentScene {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heading("Synopsis")
                    TextField("What the scene is for, in a line", text: $synopsis, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .onSubmit(save)
                    heading("Notes")
                    TextEditor(text: $notes)
                        .font(.callout)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    Text("Both go to Untangle and Three Takes with the scene, and never into the draft.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { load(scene) }
            .onChange(of: scene.id) { load(scene) }
            .onChange(of: synopsis) { schedule() }
            .onChange(of: notes) { schedule() }
            .onDisappear { pending?.cancel(); save() }
        } else {
            ContentUnavailableView("No scene", systemImage: "note.text", description: Text("Select a scene to write its synopsis and notes."))
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func load(_ scene: SceneRef) {
        pending?.cancel()
        loadedFor = scene.id
        synopsis = scene.synopsis
        notes = scene.notes
    }

    private func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard let loadedFor, loadedFor == model.currentScene?.id else { return }
        model.saveSceneNotes(synopsis: synopsis, notes: notes, for: loadedFor)
    }
}
