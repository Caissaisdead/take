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
    @State private var inText: [Prose.Note] = []
    @State private var scan: Task<Void, Never>?

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
                    heading("In the text")
                    if inText.isEmpty {
                        Text("Write [[a note]] in the prose and it is listed here, dimmed on the page and left out of every export.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(inText) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("¶\(note.paragraph + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                            Text(note.text.isEmpty ? "(empty)" : note.text)
                                .font(.callout)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.showInText(paragraph: note.paragraph, location: note.location, length: note.length) }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { load(scene); inText = model.notesInText }
            .onChange(of: scene.id) { load(scene); inText = model.notesInText }
            .onChange(of: model.loadToken) { inText = model.notesInText }
            .onChange(of: model.editCount) { rescan() }
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

    /// Half a second after the last keystroke, not on each: the scan reads the
    /// whole text.
    private func rescan() {
        scan?.cancel()
        scan = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            inText = model.notesInText
        }
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
