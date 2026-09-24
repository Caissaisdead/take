import AppKit
import Foundation
import Observation
import os
import ManuscriptKit

/// The one project the spike opens, and everything the window shows of it. Every
/// store call is wrapped so a thrown error lands in `statusLine`; the store is
/// synchronous and small, so it runs on the main actor, but never from inside
/// the text storage delegate.
@MainActor
@Observable
final class ProjectModel {
    enum Selection: Hashable {
        case main(SceneID)
        case take(Take)

        var sceneID: SceneID {
            switch self {
            case .main(let id): return id
            case .take(let take): return take.scene
            }
        }
    }

    /// A row in the binder.
    enum BinderItem: Hashable {
        case part(UUID)
        case chapter(UUID)
        case scene(SceneID)
    }

    /// What the name sheet is asking a name for.
    enum Naming: Identifiable, Hashable {
        case take
        /// A scene after `after` in its chapter, or at the end of `chapter`, or
        /// after the open scene when both are nil.
        case scene(chapter: UUID?, after: SceneID?)
        /// A chapter at the end of `part`, or of the open scene's part.
        case chapter(part: UUID?)
        case part
        case milestone
        case rename(BinderItem)

        var id: Self { self }

        /// From the toolbar or the menu: relative to whatever is open.
        static let scene = Naming.scene(chapter: nil, after: nil)
        static let chapter = Naming.chapter(part: nil)
    }

    /// The three texts a keep could not merge on its own, and the take that
    /// brought them.
    struct Conflict: Identifiable {
        let id = UUID()
        let take: Take
        let base: String
        let main: String
        let text: String
    }

    private(set) var manuscript = Manuscript(title: "")
    private(set) var selection: Selection?
    /// The text last loaded into the editor, kept current by every save so it
    /// is never staler than main. What the editor holds now is `currentText`;
    /// nothing on the keystroke path touches this.
    private(set) var editorText = ""
    /// Changes whenever the model sets `editorText`; the editor reloads on this
    /// alone, never by comparing strings.
    private(set) var loadToken = 0
    /// What the editor selects once it has loaded `editorText`; nil is the top.
    private(set) var editorSelection: NSRange?
    /// Counts user edits since launch, for anything that wants to follow typing.
    private(set) var editCount = 0
    private(set) var isDirty = false
    private(set) var takes: [Take] = []
    private(set) var discarded: [Take] = []
    private(set) var history: [Version] = []
    private(set) var milestones: [Milestone] = []
    private(set) var wordCount = 0
    private(set) var lastLoadMillis: Double?
    var statusLine = ""
    var conflict: Conflict?
    var naming: Naming?
    /// What the compare pane holds the editor against. Reset when the scene changes.
    var compareBase: CompareBase = .automatic

    /// One side of a comparison; the other is always the editor.
    enum CompareBase: Hashable, Identifiable {
        /// Main for a take; the previous version for main.
        case automatic
        case main
        case version(ObjectID)
        case milestone(String)

        var id: Self { self }
    }

    @ObservationIgnored private var store: ProjectStore?
    @ObservationIgnored private var idleSave: Task<Void, Never>?
    @ObservationIgnored private var recount: Task<Void, Never>?
    @ObservationIgnored private var bench: Task<Void, Never>?
    /// Reads the editor's text on demand, once the editor exists.
    @ObservationIgnored private var readEditor: (() -> String?)?
    /// Selects a range in the editor as it is, without a reload.
    @ObservationIgnored private var showInEditor: ((NSRange) -> Void)?
    @ObservationIgnored private let log = Logger(subsystem: "com.siddharthnigam.take", category: "editor")

    static let idleSaveDelay: Duration = .seconds(10)

    /// The folder the open project lives in.
    private(set) var projectURL: URL?
    /// Held for the life of the project so the sandbox keeps the grant.
    @ObservationIgnored private var scopedURL: URL?

    init() {
        // Bench runs always use the sample; otherwise the last project, else the sample.
        if !Self.isBenchRequested, let url = Self.lastProjectURL() {
            open(url)
        }
        if store == nil {
            open(Self.sampleFolder, seedingSample: true)
        }
        // The idle save waits ten seconds; a quit inside them must not lose
        // the text. The notice is posted on the main thread, before any
        // window goes, so the save runs whole.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isDirty else { return }
                self.save()
            }
        }
    }

    /// The window's name: the manuscript's title, or the folder's.
    var projectName: String {
        manuscript.title.isEmpty ? (projectURL?.lastPathComponent ?? "Take") : manuscript.title
    }

    // MARK: - Projects

    /// Opens the project at `url`, or makes one there when the folder is empty
    /// or missing (the sample is seeded when asked). A folder with files in it
    /// and no repository is left alone: a project without its `.git`, or any
    /// other folder, must not be written over. A failure leaves whatever was
    /// open as it was.
    func open(_ url: URL, seedingSample: Bool = false) {
        settle()
        guard !isDirty else { return }
        // Three Takes holds the store it started on; let it finish or be
        // stopped rather than write into a project that is no longer open.
        guard !isWritingTakes else {
            statusLine = "Three Takes is still writing; stop it before opening another project"
            return
        }
        untangleTask?.cancel()
        untangleTask = nil
        untangling = nil
        untangleError = nil
        isUntangling = false
        let author = Signature(name: NSFullUserName(), email: "writer@localhost")
        let scoped = url.startAccessingSecurityScopedResource() ? url : nil
        do {
            let opened: ProjectStore
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                opened = try ProjectStore.open(at: url, author: author)
            } else {
                guard seedingSample || Self.isEmptyFolder(url) else {
                    scoped?.stopAccessingSecurityScopedResource()
                    statusLine = "\(url.lastPathComponent) has files in it and is not a Take project; choose an empty folder"
                    return
                }
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                opened = try ProjectStore.create(at: url, title: url.lastPathComponent, author: author)
                if seedingSample {
                    let first = try opened.addScene(title: "A truth universally acknowledged", toChapter: nil, text: Self.sampleText())
                    let chapter = try opened.manifest().chapters.first { $0.scenes.contains { $0.id == first.id } }?.id
                    _ = try opened.addScene(title: "Netherfield", toChapter: chapter, text: Self.netherfieldText)
                }
            }
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = scoped
            store = opened
            projectURL = url
            selection = nil
            compareBase = .automatic
            mapChapter = nil
            setEditorText("", dirty: false)
            manuscript = try opened.manifest()
            refresh()
            Self.remember(url)
            statusLine = "Opened \(url.path)"
            if let first = manuscript.scenes.first {
                select(.main(first.id))
            }
        } catch {
            scoped?.stopAccessingSecurityScopedResource()
            statusLine = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Asks for a folder to open. An empty folder becomes a new project.
    func openProject() {
        Task {
            if let url = await ProjectPanels.chooseProjectFolder() { open(url) }
        }
    }

    /// Asks where to make a project, named after the folder chosen.
    func newProject() {
        Task {
            if let url = await ProjectPanels.chooseNewProjectFolder() { open(url) }
        }
    }

    func openSample() {
        open(Self.sampleFolder, seedingSample: true)
    }

    func revealInFinder() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    /// Terminal, opened on the project folder, for a writer who works with
    /// git or an agent on the real repository.
    func openInTerminal() {
        guard let projectURL else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([projectURL], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in self.statusLine = "Terminal did not open: \(error.localizedDescription)" }
            }
        }
    }

    /// A folder that is not there yet counts as empty; the Finder's own
    /// `.DS_Store` does not count as a file.
    private static func isEmptyFolder(_ url: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return true }
        return names.allSatisfy { $0 == ".DS_Store" }
    }

    private static let bookmarkKey = "LastProjectBookmark"

    private static func remember(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    /// The last project's folder, when it still holds a repository. The sandbox
    /// answers nothing about a folder outside the container until its grant is
    /// taken up, so the check runs inside one; `open` takes its own, and
    /// `remember` renews a bookmark that has gone stale.
    private static func lastProjectURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else { return nil }
        return url
    }

    /// The loaded text plus whatever has been typed since, as the editor holds
    /// it: one paragraph per line.
    var currentText: String {
        readEditor?() ?? editorText
    }

    /// `currentText` in stored form, which is what the store, the differ and
    /// the engines all read.
    private var storedText: String {
        Prose.join(Prose.paragraphsByLine(currentText))
    }

    /// The editor's last text, handed over as its view goes away (the window
    /// closing, or no scene left open), so `currentText` stays what the writer
    /// saw. Taken only while dirty: a clean editor's text is already here, and
    /// after a removal it would be the removed scene's.
    func editorGone(text: String) {
        readEditor = nil
        showInEditor = nil
        if isDirty { editorText = text }
    }

    /// The open scene as the manifest has it, whether main or a take is showing.
    var currentScene: SceneRef? {
        selection.flatMap { manuscript.scene($0.sceneID) }
    }

    var sceneTitle: String {
        currentScene?.title ?? ""
    }

    /// The scene's synopsis and notes into the manifest, when they changed.
    func saveSceneNotes(synopsis: String, notes: String, for scene: SceneID) {
        guard let store else { return }
        attempt("Note") {
            let head = try store.mainHead()
            try store.update(scene: scene, synopsis: synopsis, notes: notes)
            if try store.mainHead() != head { refresh() }
        }
    }

    var selectionLabel: String {
        switch selection {
        case .main: return "Main"
        case .take(let take): return "Take: \(take.name)"
        case nil: return "No scene"
        }
    }

    var isInTake: Bool {
        if case .take = selection { return true }
        return false
    }

    // MARK: - Editing

    /// Opens main or a take in the editor. `selecting` names a paragraph and
    /// a range within it, in the stored text's terms, to select once loaded.
    func select(_ target: Selection, selecting: (paragraph: Int, location: Int, length: Int)? = nil) {
        if isDirty {
            save()
            // A failed save keeps the edits on screen rather than dropping them.
            guard !isDirty else { return }
        }
        guard let store else { return }
        attempt("Open") {
            let text: String
            switch target {
            case .main(let id): text = try store.sceneText(id)
            case .take(let take): text = try store.takeText(take)
            }
            if selection?.sceneID != target.sceneID {
                untangling = nil
                untangleError = nil
                untangleTask?.cancel()
                isUntangling = false
            }
            selection = target
            compareBase = .automatic
            let editor = Prose.editorForm(text)
            let range = selecting.flatMap { Prose.editorRange(paragraph: $0.paragraph, location: $0.location, length: $0.length, in: editor) }
            setEditorText(editor, dirty: false, selecting: range.map { NSRange(location: $0.location, length: $0.length) })
            refresh()
        }
    }

    /// Opens what a search hit is in and selects the hit. When it is in the
    /// text already on screen, the editor is left as it is and only the
    /// selection moves, so unsaved work stays unsaved.
    func reveal(_ match: Match) {
        let target: Selection = match.take.map { Selection.take($0) } ?? Selection.main(match.scene)
        if selection == target {
            showInText(paragraph: match.paragraph, location: match.location, length: match.length)
        } else {
            select(target, selecting: (match.paragraph, match.location, match.length))
        }
    }

    /// The writer's `[[notes]]` in the text on screen, in order.
    var notesInText: [Prose.Note] {
        Prose.notes(in: storedText)
    }

    /// Selects a note, or any range given in the stored text's terms, in the
    /// text on screen.
    func showInText(paragraph: Int, location: Int, length: Int) {
        guard let range = Prose.editorRange(paragraph: paragraph, location: location, length: length, in: currentText) else { return }
        showInEditor?(NSRange(location: range.location, length: range.length))
    }

    /// Every hit of `query` in the draft, in manuscript order.
    func search(_ query: String, includingTakes: Bool) -> [Match] {
        guard let store else { return [] }
        do {
            return try store.search(query, includingTakes: includingTakes)
        } catch {
            statusLine = "Find failed: \(error.localizedDescription)"
            return []
        }
    }

    func textChanged() {
        isDirty = true
        editCount += 1
        scheduleIdleSave()
        scheduleRecount()
    }

    func save() {
        idleSave?.cancel()
        guard let store, let selection else { return }
        let text = storedText
        attempt("Save") {
            switch selection {
            case .main(let id):
                if let commit = try store.checkpoint(id, text: text) {
                    statusLine = "Checkpoint \(commit.short)"
                } else {
                    statusLine = "Nothing changed since the last checkpoint"
                }
            case .take(let take):
                let saved = try store.saveTake(take, text: text)
                self.selection = .take(saved)
                statusLine = saved.head == take.head ? "Nothing changed on \(take.name)" : "Saved \(take.name) at \(saved.head.short)"
            }
            // Same token, so the editor keeps its caret; only the fallback moves.
            editorText = Prose.editorForm(text)
            isDirty = false
            refresh()
        }
    }

    func restore(version: Version) {
        restore(at: version.id, label: version.id.short)
    }

    /// The scene as it stood at the milestone, into the editor, unsaved.
    func restore(milestone: Milestone) {
        restore(at: milestone.commit, label: milestone.name)
    }

    private func restore(at commit: ObjectID, label: String) {
        guard let store, let scene = selection?.sceneID else { return }
        attempt("Restore") {
            let text = try store.sceneText(scene, at: commit)
            setEditorText(Prose.editorForm(text), dirty: true)
            statusLine = "Restored \(label) into the editor, unsaved"
        }
    }

    /// Marks the whole draft as it is saved now. Unsaved text is saved first,
    /// so the milestone means what the writer sees.
    func markMilestone(named name: String) {
        guard let store else { return }
        settle()
        guard !isDirty else { return }
        attempt("Milestone") {
            let milestone = try store.milestone(named: name)
            refresh()
            statusLine = "Marked \(milestone.name) at \(milestone.commit.short)"
        }
    }

    /// The stress text in the editor, for the bench alone. Not marked dirty,
    /// so the idle save never commits it over the scene; only a save the
    /// writer asks for does.
    func loadStress() {
        setEditorText(Prose.editorForm(Self.stressText), dirty: false)
        statusLine = "Stress text loaded, \(wordCount) words; Save would commit it"
    }

    func recordLoad(millis: Double) {
        lastLoadMillis = millis
        log.info("editor load \(millis, format: .fixed(precision: 1)) ms for \(self.wordCount) words")
    }

    // MARK: - Shape

    /// Where a new scene goes: the selected scene's chapter, else the last one.
    var currentChapter: UUID? {
        selection.flatMap { manuscript.chapter(containing: $0.sceneID)?.id } ?? manuscript.chapters.last?.id
    }

    /// Where a new chapter goes: the current chapter's part, else the last one.
    var currentPart: UUID? {
        currentChapter.flatMap { manuscript.part(containing: $0)?.id } ?? manuscript.parts.last?.id
    }

    func title(of item: BinderItem) -> String {
        switch item {
        case .part(let id): return manuscript.part(id)?.title ?? ""
        case .chapter(let id): return manuscript.chapter(id)?.title ?? ""
        case .scene(let id): return manuscript.scene(id)?.title ?? ""
        }
    }

    /// Adds and opens an empty scene: after `after`, else at the end of
    /// `chapter`, else after the open scene.
    func addScene(named title: String, inChapter chapter: UUID?, after: SceneID?) {
        guard let store else { return }
        settle()
        guard !isDirty else { return }
        let anchor = after ?? (chapter == nil ? selection?.sceneID : nil)
        let destination = anchor.flatMap { manuscript.chapter(containing: $0) } ?? chapter.flatMap { manuscript.chapter($0) }
        let index = anchor.flatMap { id in destination?.scenes.firstIndex { $0.id == id }.map { $0 + 1 } }
        attempt("New scene") {
            let scene = try store.addScene(title: title, toChapter: destination?.id ?? currentChapter, at: index, text: "")
            refresh()
            select(.main(scene.id))
            statusLine = "Added \(title)"
        }
    }

    /// Adds a chapter at the end of `part`, else of the open scene's part.
    func addChapter(named title: String, inPart part: UUID?) {
        guard let store else { return }
        attempt("New chapter") {
            _ = try store.addChapter(title: title, toPart: part ?? currentPart)
            refresh()
            statusLine = "Added chapter \(title)"
        }
    }

    func addPart(named title: String) {
        guard let store else { return }
        attempt("New part") {
            _ = try store.addPart(title: title)
            refresh()
            statusLine = "Added part \(title)"
        }
    }

    func rename(_ item: BinderItem, to title: String) {
        guard let store else { return }
        attempt("Rename") {
            switch item {
            case .part(let id): try store.rename(part: id, to: title)
            case .chapter(let id): try store.rename(chapter: id, to: title)
            case .scene(let id): try store.rename(scene: id, to: title)
            }
            refresh()
            statusLine = "Renamed to \(title)"
        }
    }

    /// `index` counts among the chapter's scenes after the scene is taken out.
    func move(scene id: SceneID, toChapter chapter: UUID, at index: Int) {
        guard let store else { return }
        attempt("Move") {
            try store.move(scene: id, toChapter: chapter, at: index)
            refresh()
        }
    }

    /// One step up (-1) or down (+1) among its part's chapters.
    func move(chapter id: UUID, by offset: Int) {
        guard let store, let part = manuscript.part(containing: id),
              let index = part.chapters.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard part.chapters.indices.contains(target) else { return }
        attempt("Move") {
            try store.move(chapter: id, toPart: part.id, at: target)
            refresh()
        }
    }

    /// To the end of another part.
    func move(chapter id: UUID, toPart part: UUID) {
        guard let store else { return }
        attempt("Move") {
            try store.move(chapter: id, toPart: part, at: .max)
            refresh()
        }
    }

    func move(part id: UUID, by offset: Int) {
        guard let store, let index = manuscript.parts.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard manuscript.parts.indices.contains(target) else { return }
        attempt("Move") {
            try store.move(part: id, to: target)
            refresh()
        }
    }

    /// Removes the item and whatever it holds. A removed scene that was open
    /// leaves the editor empty once it is gone; its edits go with it. A
    /// removal that fails leaves the editor as it was.
    func remove(_ item: BinderItem) {
        guard let store else { return }
        let title = title(of: item)
        let gone: Set<SceneID>
        switch item {
        case .part(let id): gone = Set(manuscript.part(id)?.chapters.flatMap(\.scenes).map(\.id) ?? [])
        case .chapter(let id): gone = Set(manuscript.chapter(id)?.scenes.map(\.id) ?? [])
        case .scene(let id): gone = [id]
        }
        attempt("Remove") {
            switch item {
            case .part(let id): try store.remove(part: id)
            case .chapter(let id): try store.remove(chapter: id)
            case .scene(let id): try store.remove(scene: id)
            }
            if let current = selection?.sceneID, gone.contains(current) {
                idleSave?.cancel()
                isDirty = false
                selection = nil
                setEditorText("", dirty: false)
            }
            refresh()
            statusLine = "Removed \(title); it stays in history"
        }
    }

    /// Saves whatever is dirty so a shape change never sits on unsaved text.
    private func settle() {
        if isDirty { save() }
    }

    // MARK: - Map

    /// One box on the chapter map.
    struct MapNode: Identifiable, Hashable {
        enum Kind: Hashable {
            case main
            case take(Take)
            case discarded(Take)
        }

        var id: String
        var kind: Kind
        var title: String
        var words: Int
        /// Words added and removed against main; nil for main itself.
        var delta: (added: Int, removed: Int)?
        /// Commits of the take's own, so a take never saved reads as empty.
        var saves: Int
        /// The scene's synopsis, on main's node only.
        var synopsis = ""

        static func == (lhs: MapNode, rhs: MapNode) -> Bool { lhs.id == rhs.id && lhs.words == rhs.words && lhs.saves == rhs.saves && lhs.synopsis == rhs.synopsis }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// A scene on the map: main on the line, its takes hanging below.
    struct MapColumn: Identifiable {
        var id: SceneID { scene.id }
        var scene: SceneRef
        var main: MapNode
        var takes: [MapNode]
    }

    /// Bumped by every refresh, so the map knows when to rebuild.
    private(set) var mapVersion = 0

    /// The chapter the map shows; nil means the open scene's chapter.
    var mapChapter: UUID?

    var mapChapterID: UUID? {
        mapChapter.flatMap { manuscript.chapter($0)?.id } ?? currentChapter
    }

    /// Every scene of the chapter with its live and discarded takes, each
    /// measured against main. Diffs run here, so call it when the map shows,
    /// not on every keystroke.
    func chapterMap(_ chapterID: UUID) -> [MapColumn] {
        guard let store, let chapter = manuscript.chapter(chapterID) else { return [] }
        var columns: [MapColumn] = []
        for scene in chapter.scenes {
            do {
                let mainText = try store.sceneText(scene.id)
                let main = MapNode(id: "main:\(scene.id.uuid.uuidString)", kind: .main, title: scene.title, words: Prose.wordCount(Prose.withoutNotes(mainText)), delta: nil, saves: 0, synopsis: scene.synopsis)
                var takes: [MapNode] = []
                for take in try store.takes(for: scene.id) {
                    takes.append(try node(for: take, against: mainText, discarded: false))
                }
                for take in try store.discardedTakes(for: scene.id) {
                    takes.append(try node(for: take, against: mainText, discarded: true))
                }
                columns.append(MapColumn(scene: scene, main: main, takes: takes))
            } catch {
                statusLine = "Map failed: \(error.localizedDescription)"
            }
        }
        return columns
    }

    private func node(for take: Take, against mainText: String, discarded: Bool) throws -> MapNode {
        guard let store else { throw ProjectStoreError.unbornMain }
        let text = try store.takeText(take)
        let summary = ProseDiffer.diff(old: mainText, new: text).summary
        let saves = try store.repository.log(from: take.head, limit: 200).prefix { $0.id != take.base }.count
        return MapNode(
            id: take.id,
            kind: discarded ? .discarded(take) : .take(take),
            title: take.name,
            words: Prose.wordCount(Prose.withoutNotes(text)),
            delta: (summary.wordsAdded, summary.wordsRemoved),
            saves: saves)
    }

    /// Opens what a map node stands for. A discarded take only reports itself.
    func open(_ node: MapNode) {
        switch node.kind {
        case .main:
            if let id = SceneID(mapID: node.id) { select(.main(id)) }
        case .take(let take):
            select(.take(take))
        case .discarded(let take):
            restore(discarded: take)
        }
    }

    // MARK: - Untangle

    private(set) var untangling: Untangling?
    private(set) var untangleError: String?
    private(set) var isUntangling = false
    @ObservationIgnored private var untangleTask: Task<Void, Never>?
    @ObservationIgnored private let untangler = Untangler()

    var untangleUnavailable: String? { untangler.unavailableReason }

    /// Runs Untangle on the open scene's current text. The result is kept
    /// until another scene opens or it runs again.
    func untangle() {
        guard selection != nil, !isUntangling else { return }
        let title = sceneTitle
        let synopsis = currentScene?.synopsis ?? ""
        let text = storedText
        isUntangling = true
        untangleError = nil
        untangleTask?.cancel()
        untangleTask = Task {
            do {
                let result = try await untangler.untangle(scene: title, synopsis: synopsis, text: text)
                guard !Task.isCancelled else { return }
                untangling = result
                statusLine = "Untangled \(title)"
            } catch {
                guard !Task.isCancelled else { return }
                untangleError = error.localizedDescription
                statusLine = "Untangle: \(error.localizedDescription)"
            }
            isUntangling = false
        }
    }

    // MARK: - Three Takes

    /// One angle's progress in the sheet.
    struct TakeRun: Identifiable, Hashable {
        enum State: Hashable { case waiting, writing, done(String), failed(String) }
        let angle: ThreeTakes.Angle
        var state: State = .waiting
        var id: String { angle.id }
    }

    /// Non-nil while the sheet is up; the runs it shows.
    var takeRuns: [TakeRun]?
    /// The consent sheet, up until the writer answers.
    var consent: Bool = false
    @ObservationIgnored private var takesTask: Task<Void, Never>?

    var isWritingTakes: Bool {
        takeRuns?.contains { $0.state == .writing || $0.state == .waiting } ?? false
    }

    /// Draft > Three Takes: asks once if the writer has not settled consent,
    /// then writes the three.
    func requestThreeTakes() {
        guard selection != nil, !isWritingTakes else { return }
        guard ClaudeClient.hasKey else {
            statusLine = "Add an Anthropic API key in Settings first."
            return
        }
        if ConsentGate.isSettled {
            writeThreeTakes()
        } else {
            consent = true
        }
    }

    /// Writes the takes one after another from main's copy of the scene, so
    /// unsaved text is saved first and every take starts at the same base.
    func writeThreeTakes() {
        guard let store, let scene = selection?.sceneID else { return }
        settle()
        guard !isDirty else { return }
        if isInTake { select(.main(scene)) }
        let brief = ThreeTakes.Brief(
            manuscriptTitle: manuscript.title,
            sceneTitle: sceneTitle,
            synopsis: currentScene?.synopsis ?? "",
            notes: currentScene?.notes ?? "",
            draft: (try? store.sceneText(scene)) ?? "",
            before: neighbour(of: scene, offset: -1).flatMap { try? store.sceneText($0) },
            after: neighbour(of: scene, offset: 1).flatMap { try? store.sceneText($0) },
            untangling: untangling)
        takeRuns = ThreeTakes.angles.map { TakeRun(angle: $0) }
        takesTask?.cancel()
        takesTask = Task {
            var written: [(angle: ThreeTakes.Angle, text: String)] = []
            for (index, angle) in ThreeTakes.angles.enumerated() {
                guard !Task.isCancelled else { return }
                takeRuns?[index].state = .writing
                do {
                    let reply = try await ClaudeClient.complete(
                        system: ThreeTakes.system,
                        user: ThreeTakes.prompt(for: brief, angle: angle, previous: written))
                    guard !Task.isCancelled else { return }
                    let text = Prose.normalize(reply.text)
                    let take = try store.createTake(for: scene, name: "Take \(angle.id): \(angle.name)")
                    try store.saveTake(take, text: text)
                    written.append((angle, text))
                    let words = "\(Prose.wordCount(text)) words"
                    takeRuns?[index].state = .done(reply.wasCut ? "\(words), cut short at the length limit" : words)
                    refresh()
                } catch {
                    // A stop mid-call surfaces as an error; it is not a failure.
                    guard !Task.isCancelled else { return }
                    takeRuns?[index].state = .failed(error.localizedDescription)
                }
            }
            guard !Task.isCancelled else { return }
            let made = written.count
            statusLine = made == 3 ? "Three takes written; pick one in the map or the inspector" : "\(made) of 3 takes written"
            refresh()
        }
    }

    func cancelThreeTakes() {
        takesTask?.cancel()
        takesTask = nil
        takeRuns = nil
        refresh()
    }

    /// The scene before or after this one in manuscript order.
    private func neighbour(of scene: SceneID, offset: Int) -> SceneID? {
        let all = manuscript.scenes.map(\.id)
        guard let index = all.firstIndex(of: scene) else { return nil }
        let target = index + offset
        return all.indices.contains(target) ? all[target] : nil
    }

    // MARK: - Export

    /// The draft on main as Markdown, after saving whatever is unsaved so the
    /// export matches the screen.
    func exportMarkdown() {
        guard let store else { return }
        settle()
        guard !isDirty else { return }
        let files: [ExportFile]
        do {
            files = try store.exportMarkdown()
        } catch {
            statusLine = "Export failed: \(error.localizedDescription)"
            return
        }
        let name = MarkdownExport.fileName(manuscript.title, fallback: "Manuscript")
        Task {
            do {
                if let folder = try await ExportCoordinator.exportMarkdown(files, suggestedName: name) {
                    statusLine = "Exported \(files.count) files to \(folder.lastPathComponent)"
                }
            } catch {
                statusLine = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    /// The draft on main as a Word document.
    func exportDocx() {
        guard let store else { return }
        settle()
        guard !isDirty else { return }
        let data: Data
        do {
            let head = try store.mainHead()
            data = try DocxWriter.data(for: try store.manifest()) { try store.sceneText($0, at: head) }
        } catch {
            statusLine = "Export failed: \(error.localizedDescription)"
            return
        }
        let name = MarkdownExport.fileName(manuscript.title, fallback: "Manuscript")
        Task {
            do {
                if let url = try await ExportCoordinator.exportDocx(data, suggestedName: name) {
                    statusLine = "Exported \(url.lastPathComponent)"
                }
            } catch {
                statusLine = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Bench

    /// With `-TakeBench` on the command line (or the `TakeBench` default set),
    /// runs the benchmark once the editor exists, writes `bench.json` beside the
    /// project and quits, so a harness needs nothing from the UI.
    func editorReady(_ textView: ProseTextView) {
        readEditor = { [weak textView] in textView?.string }
        showInEditor = { [weak textView] range in
            textView?.show(range)
            textView?.window?.makeFirstResponder(textView)
        }
        guard Self.isBenchRequested, bench == nil else { return }
        bench = Task { await runBench(on: textView) }
    }

    private func runBench(on textView: ProseTextView) async {
        // Measured in the real window: wait for it to be up and to have laid out a
        // first viewport, with a cap so a stuck launch still ends in a quit.
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let window = textView.window, window.isVisible, !textView.visibleRect.isEmpty,
               let viewport = textView.textLayoutManager?.textViewportLayoutController.viewportBounds, viewport.height > 0 {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let result = Bench(textView: textView).run([("scene", Self.sampleText()), ("stress", Self.stressText)])
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(result).write(to: Self.benchFile)
            log.info("bench written to \(Self.benchFile.path)")
        } catch {
            log.error("bench not written: \(error.localizedDescription)")
        }
        // Nothing typed here belongs in the project's history.
        idleSave?.cancel()
        recount?.cancel()
        isDirty = false
        NSApp.terminate(nil)
    }

    // MARK: - Takes

    func newTake(named name: String) {
        guard let store, let scene = selection?.sceneID else { return }
        if isDirty {
            save()
            guard !isDirty else { return }
        }
        attempt("New take") {
            let take = try store.createTake(for: scene, name: name)
            statusLine = "Started \(take.name) from \(take.base.short)"
            select(.take(take))
        }
    }

    func keep() {
        guard let store, isInTake else { return }
        if isDirty {
            save()
            guard !isDirty else { return }
        }
        // save() refreshes the selection with the take's new head.
        guard case .take(let take)? = selection else { return }
        attempt("Keep") {
            switch try store.keep(take) {
            case .kept(let merge):
                statusLine = "Kept \(take.name) as \(merge.short)"
                select(.main(take.scene))
            case .conflict(let base, let main, let mine):
                conflict = Conflict(take: take, base: base, main: main, text: mine)
                statusLine = "Main changed since \(take.name) began; nothing written"
            }
        }
    }

    /// Settles a conflicted keep with the whole scene from one side.
    func settle(_ conflict: Conflict, choosing side: KeepSide) {
        guard let store else { return }
        self.conflict = nil
        attempt("Keep") {
            let commit = try store.keep(conflict.take, choosing: side)
            switch side {
            case .take: statusLine = "Kept \(conflict.take.name) over main as \(commit.short)"
            case .main: statusLine = "Kept main; \(conflict.take.name) is recorded and gone"
            }
            select(.main(conflict.take.scene))
        }
    }

    /// Brings a discarded take back to the scene's list and opens it.
    func restore(discarded take: Take) {
        guard let store else { return }
        if isDirty {
            save()
            guard !isDirty else { return }
        }
        attempt("Restore take") {
            let restored = try store.restore(discarded: take)
            statusLine = "Brought back \(restored.name)"
            select(.take(restored))
        }
    }

    func discard() {
        guard let store, case .take(let take)? = selection else { return }
        idleSave?.cancel()
        isDirty = false
        attempt("Discard") {
            try store.discard(take)
            statusLine = "Discarded \(take.name)"
            select(.main(take.scene))
        }
    }

    // MARK: - Compare

    /// The bases the compare pane can offer for the open scene: main for a take,
    /// every version in the scene's history and every milestone.
    var compareChoices: [(base: CompareBase, label: String)] {
        guard selection != nil else { return [] }
        var choices: [(CompareBase, String)] = [(.automatic, isInTake ? "Main" : "Previous version")]
        if isInTake { choices.append((.main, "Main now")) }
        for milestone in milestones {
            choices.append((.milestone(milestone.id), "Milestone: \(milestone.name)"))
        }
        for version in history {
            choices.append((.version(version.id), "\(version.message) · \(Self.short(version.date))"))
        }
        return choices.map { (base: $0.0, label: $0.1) }
    }

    /// The editor against the chosen base. Automatic is main's copy for a take,
    /// and the version before the current one for main, when there is one.
    func compare() -> ProseDiff? {
        guard let store, let selection else { return nil }
        let scene = selection.sceneID
        do {
            let commit: ObjectID?
            switch compareBase {
            case .automatic:
                if case .take = selection {
                    commit = try store.mainHead()
                } else {
                    commit = history.count > 1 ? history[1].id : nil
                }
            case .main:
                commit = try store.mainHead()
            case .version(let id):
                commit = id
            case .milestone(let ref):
                commit = milestones.first { $0.id == ref }?.commit
            }
            guard let commit else { return nil }
            return ProseDiffer.diff(old: try store.sceneText(scene, at: commit), new: storedText)
        } catch {
            statusLine = "Compare failed: \(error.localizedDescription)"
            return nil
        }
    }

    private static func short(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    // MARK: - Plumbing

    private func refresh() {
        guard let store else { return }
        mapVersion += 1
        attempt("Refresh") {
            manuscript = try store.manifest()
            milestones = try store.milestones()
            guard let scene = selection?.sceneID else {
                takes = []
                discarded = []
                history = []
                return
            }
            takes = try store.takes(for: scene)
            discarded = try store.discardedTakes(for: scene)
            history = try store.history(of: scene)
            if case .take(let current)? = selection, let fresh = takes.first(where: { $0.id == current.id }) {
                selection = .take(fresh)
            }
        }
    }

    private func setEditorText(_ text: String, dirty: Bool, selecting: NSRange? = nil) {
        idleSave?.cancel()
        recount?.cancel()
        editorText = text
        editorSelection = selecting
        loadToken += 1
        isDirty = dirty
        wordCount = Prose.wordCount(Prose.withoutNotes(text))
        if dirty { scheduleIdleSave() }
    }

    private func scheduleIdleSave() {
        idleSave?.cancel()
        idleSave = Task { [weak self] in
            try? await Task.sleep(for: Self.idleSaveDelay)
            guard !Task.isCancelled, let self, self.isDirty else { return }
            self.save()
        }
    }

    // Counting 20k words on every keystroke would blur the typing measurement:
    // each keystroke restarts the wait, so a burst is counted once, 300 ms after
    // its last key.
    private func scheduleRecount() {
        recount?.cancel()
        recount = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.wordCount = Prose.wordCount(Prose.withoutNotes(self.currentText))
        }
    }

    private func attempt(_ what: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            statusLine = "\(what) failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Fixtures

    /// The seeded sample, in the app's own container.
    static var sampleFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Take", isDirectory: true)
            .appendingPathComponent("Sample Project", isDirectory: true)
    }

    static let isBenchRequested = CommandLine.arguments.contains("-TakeBench") || UserDefaults.standard.bool(forKey: "TakeBench")

    static var benchFile: URL {
        sampleFolder.deletingLastPathComponent().appendingPathComponent("bench.json")
    }

    /// The sample scene four times over: about 20k words.
    static var stressText: String {
        let block = sampleText().trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(repeating: block, count: 4).joined(separator: "\n\n") + "\n"
    }

    static func sampleText() -> String {
        let url = Bundle.main.url(forResource: "sample-scene", withExtension: "md", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "sample-scene", withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The sample scene is missing from the app bundle.\n"
        }
        return text
    }

    static let netherfieldText = """
    The carriage turned in at the gates a little after four, and the house came up out of the park all at once, broad and pale and entirely too large for one man to be living in alone.

    Mr. Bingley met them on the steps himself, which nobody had expected, and talked so easily about the drive and the weather that Jane forgot for a whole minute to be nervous.

    Elizabeth, coming last, took the measure of the tall gentleman at the window before he had taken hers, and decided, on no evidence at all, that she did not like him.

    """
}


extension SceneID {
    /// The scene behind a `main:` map node id.
    fileprivate init?(mapID: String) {
        guard mapID.hasPrefix("main:"), let uuid = UUID(uuidString: String(mapID.dropFirst(5))) else { return nil }
        self.init(uuid: uuid)
    }
}
