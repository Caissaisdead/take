import SwiftUI
import UniformTypeIdentifiers
import ManuscriptKit

/// The binder: parts, chapters and scenes in the sidebar. Only scenes select.
/// Scenes drag within and between chapters; chapters and parts move by menu,
/// since a section header is nothing the list will let go of.
struct BinderView: View {
    @Environment(ProjectModel.self) private var model
    @State private var removing: ProjectModel.BinderItem?

    var body: some View {
        List(selection: selectionBinding) {
            if model.manuscript.parts.isEmpty {
                ContentUnavailableView {
                    Label("No scenes yet", systemImage: "book.closed")
                } description: {
                    Text("Add a scene to begin.")
                } actions: {
                    Button("New Scene…") { model.naming = .scene }
                }
            }
            ForEach(model.manuscript.parts) { part in
                if showsPartHeaders {
                    PartHeader(part: part, removing: $removing)
                }
                ForEach(part.chapters) { chapter in
                    Section {
                        ForEach(chapter.scenes) { scene in
                            SceneRow(scene: scene, removing: $removing)
                                .tag(scene.id)
                                .itemProvider { NSItemProvider(object: scene.id.uuid.uuidString as NSString) }
                        }
                        .onMove { offsets, destination in
                            guard let source = offsets.first else { return }
                            model.move(scene: chapter.scenes[source].id, toChapter: chapter.id, at: destination > source ? destination - 1 : destination)
                        }
                        .onInsert(of: [.utf8PlainText, .plainText]) { index, providers in
                            draggedScene(in: providers) { model.move(scene: $0, toChapter: chapter.id, at: index) }
                        }
                        if chapter.scenes.isEmpty {
                            EmptyChapterRow(chapter: chapter)
                        }
                    } header: {
                        ChapterHeader(chapter: chapter, removing: $removing)
                    }
                }
            }
            if !model.manuscript.scenes.isEmpty {
                Section {
                    TotalsRow()
                        .selectionDisabled()
                }
            }
            if !model.removed.isEmpty {
                Section("Recently removed") {
                    ForEach(model.removed) { removed in
                        RemovedRow(removed: removed)
                            .selectionDisabled()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(removalTitle, isPresented: removingBinding, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let removing { model.remove(removing) }
            }
        } message: {
            Text(removalMessage)
        }
    }

    /// One untitled part is no part at all.
    private var showsPartHeaders: Bool {
        model.manuscript.usesParts
    }

    private var selectionBinding: Binding<SceneID?> {
        Binding(
            get: { model.selection?.sceneID },
            set: { id in
                // Clicking empty space clears the list selection; the editor keeps its scene.
                guard let id, id != model.selection?.sceneID else { return }
                model.select(.main(id))
            }
        )
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var removalTitle: String {
        guard let removing else { return "" }
        let title = model.title(of: removing)
        switch removing {
        case .part: return "Remove part “\(title)” and everything in it?"
        case .chapter: return "Remove chapter “\(title)” and its scenes?"
        case .scene: return "Remove “\(title)”?"
        }
    }

    private var removalMessage: String {
        "The text stays in the project's history. Unsaved edits to a removed scene are dropped."
    }

    /// Reads the scene id a drag carries; the move runs on the main actor once it is loaded.
    private func draggedScene(in providers: [NSItemProvider], then move: @escaping @MainActor (SceneID) -> Void) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let uuid = UUID(uuidString: string) else { return }
            Task { @MainActor in move(SceneID(uuid: uuid)) }
        }
    }
}

private struct PartHeader: View {
    @Environment(ProjectModel.self) private var model
    let part: Part
    @Binding var removing: ProjectModel.BinderItem?

    var body: some View {
        Text(part.title.isEmpty ? "Untitled Part" : part.title)
            .font(.headline)
            .foregroundStyle(part.title.isEmpty ? .secondary : .primary)
            .padding(.top, 6)
            .selectionDisabled()
            .contextMenu {
                Button("New Chapter in Part…") { model.naming = .chapter(part: part.id) }
                Button("Rename Part…") { model.naming = .rename(.part(part.id)) }
                Divider()
                Button("Move Part Up") { model.move(part: part.id, by: -1) }
                    .disabled(model.manuscript.parts.first?.id == part.id)
                Button("Move Part Down") { model.move(part: part.id, by: 1) }
                    .disabled(model.manuscript.parts.last?.id == part.id)
                Divider()
                Button("Remove Part…", role: .destructive) { removing = .part(part.id) }
            }
    }
}

private struct ChapterHeader: View {
    @Environment(ProjectModel.self) private var model
    let chapter: Chapter
    @Binding var removing: ProjectModel.BinderItem?

    var body: some View {
        HStack {
            Text(chapter.title)
            Spacer(minLength: 6)
            Text(model.words(in: chapter).formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("Words in the chapter, on main")
        }
            .contextMenu {
                Button("New Scene in Chapter…") { model.naming = .scene(chapter: chapter.id, after: nil) }
                Button("Rename Chapter…") { model.naming = .rename(.chapter(chapter.id)) }
                Divider()
                Button("Move Chapter Up") { model.move(chapter: chapter.id, by: -1) }
                    .disabled(siblings.first?.id == chapter.id)
                Button("Move Chapter Down") { model.move(chapter: chapter.id, by: 1) }
                    .disabled(siblings.last?.id == chapter.id)
                if model.manuscript.parts.count > 1 {
                    Menu("Move to Part") {
                        ForEach(model.manuscript.parts) { part in
                            Button(part.title.isEmpty ? "Untitled Part" : part.title) {
                                model.move(chapter: chapter.id, toPart: part.id)
                            }
                            .disabled(part.id == model.manuscript.part(containing: chapter.id)?.id)
                        }
                    }
                }
                Divider()
                Button("Remove Chapter…", role: .destructive) { removing = .chapter(chapter.id) }
            }
    }

    private var siblings: [Chapter] {
        model.manuscript.part(containing: chapter.id)?.chapters ?? []
    }
}

private struct SceneRow: View {
    @Environment(ProjectModel.self) private var model
    let scene: SceneRef
    @Binding var removing: ProjectModel.BinderItem?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(scene.title)
                if !scene.synopsis.isEmpty {
                    Text(scene.synopsis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "doc.text")
        }
            .contextMenu {
                Button("Rename Scene…") { model.naming = .rename(.scene(scene.id)) }
                Button("New Scene After…") { model.naming = .scene(chapter: nil, after: scene.id) }
                Divider()
                Button("Remove Scene…", role: .destructive) { removing = .scene(scene.id) }
            }
    }
}

/// A scene history still has, with the chapter it left and a way back.
private struct RemovedRow: View {
    @Environment(ProjectModel.self) private var model
    let removed: RemovedScene

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(removed.scene.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(removed.chapterTitle.isEmpty ? "Untitled Chapter" : removed.chapterTitle) · \(removed.date, format: .dateTime.month(.abbreviated).day())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Restore") { model.restore(removed: removed) }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Put the scene back, with its text and its takes")
        }
    }
}

/// The whole draft's words, against the target when there is one.
private struct TotalsRow: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(model.totalWords.formatted()) words")
                    .monospacedDigit()
                Spacer(minLength: 4)
                if let target = model.manuscript.target {
                    Text("of \(target.formatted())")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            if let target = model.manuscript.target, target > 0 {
                ProgressView(value: min(Double(model.totalWords) / Double(target), 1))
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Targets…") { model.showTargets = true }
        }
        .help("Draft > Targets… sets the whole draft's target and the day's")
    }
}

/// A chapter with nothing in it still needs somewhere to drop a scene.
private struct EmptyChapterRow: View {
    @Environment(ProjectModel.self) private var model
    let chapter: Chapter
    @State private var targeted = false

    var body: some View {
        Text("No scenes")
            .foregroundStyle(targeted ? .primary : .tertiary)
            .italic()
            .selectionDisabled()
            .onDrop(of: [.utf8PlainText, .plainText], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let string = object as? String, let uuid = UUID(uuidString: string) else { return }
                    Task { @MainActor in model.move(scene: SceneID(uuid: uuid), toChapter: chapter.id, at: 0) }
                }
                return true
            }
    }
}
