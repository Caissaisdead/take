import SwiftUI
import ManuscriptKit

/// The manuscript as a list: chapters as sections, parts as larger headers
/// when the draft uses them, one row per scene. The bottom holds the total
/// against the target and the scenes recently removed.
struct MobileBinderView: View {
    @Environment(ProjectModel.self) private var model
    @Binding var path: [Route]
    @State private var removing: ProjectModel.BinderItem?
    @State private var moving: SceneRef?
    @State private var showTargets = false

    var body: some View {
        List {
            ForEach(model.manuscript.parts) { part in
                if model.manuscript.usesParts {
                    Section {
                        EmptyView()
                    } header: {
                        PartHeader(part: part, removing: $removing)
                    }
                }
                ForEach(part.chapters) { chapter in
                    Section {
                        ForEach(chapter.scenes) { scene in
                            SceneRow(scene: scene, words: model.sceneWords[scene.id] ?? 0)
                                .contentShape(Rectangle())
                                .onTapGesture { open(scene) }
                                .swipeActions(edge: .trailing) {
                                    Button("Remove", systemImage: "trash", role: .destructive) { removing = .scene(scene.id) }
                                    Button("Rename", systemImage: "pencil") { model.naming = .rename(.scene(scene.id)) }
                                }
                                .contextMenu {
                                    Button("New Scene After…", systemImage: "plus") { model.naming = .scene(chapter: nil, after: scene.id) }
                                    Button("Move…", systemImage: "arrow.up.arrow.down") { moving = scene }
                                    Button("Rename…", systemImage: "pencil") { model.naming = .rename(.scene(scene.id)) }
                                    Divider()
                                    Button("Remove", systemImage: "trash", role: .destructive) { removing = .scene(scene.id) }
                                }
                        }
                        if chapter.scenes.isEmpty {
                            Text("No scenes yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } header: {
                        ChapterHeader(chapter: chapter, words: model.words(in: chapter), removing: $removing)
                    }
                }
            }
            Section {
                TotalsRow(showTargets: $showTargets)
            }
            if !model.removed.isEmpty {
                Section("Recently removed") {
                    ForEach(model.removed) { removed in
                        RemovedRow(removed: removed)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.projectName)
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Scene", systemImage: "plus") { model.naming = .scene }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("New Chapter…", systemImage: "folder.badge.plus") { model.naming = .chapter }
                    Button("New Part…", systemImage: "square.stack") { model.naming = .part }
                    Button("Mark Milestone…", systemImage: "flag") { model.naming = .milestone }
                        .disabled(model.manuscript.scenes.isEmpty)
                    Button("Targets…", systemImage: "target") { showTargets = true }
                    Divider()
                    Button("Pull", systemImage: "icloud.and.arrow.down") { model.pull() }
                        .disabled(model.backupRemote.isEmpty || model.isPulling || model.isBackingUp)
                    Button("Back Up", systemImage: "icloud.and.arrow.up") { model.backUp() }
                        .disabled(model.backupRemote.isEmpty || model.isPulling || model.isBackingUp)
                }
            }
        }
        .namePrompt()
        .sheet(isPresented: $showTargets) { MobileTargetsSheet() }
        .sheet(item: $moving) { scene in MoveSheet(scene: scene) }
        .sheet(isPresented: Binding(get: { model.pullDivergence != nil }, set: { if !$0 { model.decidePullLater() } })) {
            PullConflictSheet()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let removing { model.remove(removing) }
            }
        } message: {
            Text("It stays in history and can be put back from Recently removed.")
        }
    }

    private func open(_ scene: SceneRef) {
        model.select(.main(scene.id))
        path.append(.scene(scene.id))
    }

    /// "today +812 · backed up 3 min ago"
    private var subtitle: String {
        let signed = model.wordsToday >= 0 ? "+\(model.wordsToday.formatted())" : "−\((-model.wordsToday).formatted())"
        var parts = ["today \(signed)"]
        if let last = model.lastBackup {
            parts.append("backed up \(last.formatted(.relative(presentation: .named)))")
        } else if let last = model.lastPull {
            parts.append("pulled \(last.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    private var removalTitle: String {
        guard let removing else { return "" }
        return "Remove “\(model.title(of: removing))”?"
    }
}

private struct PartHeader: View {
    @Environment(ProjectModel.self) private var model
    let part: Part
    @Binding var removing: ProjectModel.BinderItem?

    var body: some View {
        HStack {
            Text(part.title.isEmpty ? "Untitled Part" : part.title)
                .font(.title3.weight(.semibold))
                .textCase(nil)
            Spacer()
            Menu {
                Button("New Chapter in Part…") { model.naming = .chapter(part: part.id) }
                Button("Rename Part…") { model.naming = .rename(.part(part.id)) }
                Button("Move Part Up") { model.move(part: part.id, by: -1) }
                Button("Move Part Down") { model.move(part: part.id, by: 1) }
                Divider()
                Button("Remove Part", role: .destructive) { removing = .part(part.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

private struct ChapterHeader: View {
    @Environment(ProjectModel.self) private var model
    let chapter: Chapter
    let words: Int
    @Binding var removing: ProjectModel.BinderItem?

    var body: some View {
        HStack {
            Text(chapter.title.isEmpty ? "Untitled Chapter" : chapter.title)
                .textCase(nil)
            Spacer()
            Text(words.formatted())
                .monospacedDigit()
            Menu {
                Button("New Scene in Chapter…") { model.naming = .scene(chapter: chapter.id, after: nil) }
                Button("Rename Chapter…") { model.naming = .rename(.chapter(chapter.id)) }
                Button("Move Chapter Up") { model.move(chapter: chapter.id, by: -1) }
                Button("Move Chapter Down") { model.move(chapter: chapter.id, by: 1) }
                if model.manuscript.usesParts {
                    Menu("Move to Part") {
                        ForEach(model.manuscript.parts) { part in
                            Button(part.title.isEmpty ? "Untitled Part" : part.title) { model.move(chapter: chapter.id, toPart: part.id) }
                        }
                    }
                }
                Divider()
                Button("Remove Chapter", role: .destructive) { removing = .chapter(chapter.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

private struct SceneRow: View {
    let scene: SceneRef
    let words: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title.isEmpty ? "Untitled Scene" : scene.title)
                if !scene.synopsis.isEmpty {
                    Text(scene.synopsis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(words.formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct RemovedRow: View {
    @Environment(ProjectModel.self) private var model
    let removed: RemovedScene

    var body: some View {
        HStack(spacing: 8) {
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
                .font(.caption)
        }
    }
}

/// The whole draft's words, against the target when there is one.
private struct TotalsRow: View {
    @Environment(ProjectModel.self) private var model
    @Binding var showTargets: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if let target = model.manuscript.target, target > 0 {
                ProgressView(value: min(Double(model.totalWords) / Double(target), 1))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showTargets = true }
    }
}
