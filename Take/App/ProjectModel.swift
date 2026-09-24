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

    /// The three texts a keep could not merge on its own.
    struct Conflict: Identifiable {
        let id = UUID()
        let base: String
        let main: String
        let take: String
    }

    private(set) var manuscript = Manuscript(title: "")
    private(set) var selection: Selection?
    /// The text last loaded into the editor. What the editor holds now is
    /// `currentText`; nothing on the keystroke path touches this.
    private(set) var editorText = ""
    /// Changes whenever the model sets `editorText`; the editor reloads on this
    /// alone, never by comparing strings.
    private(set) var loadToken = 0
    /// Counts user edits since launch, for anything that wants to follow typing.
    private(set) var editCount = 0
    private(set) var isDirty = false
    private(set) var takes: [Take] = []
    private(set) var history: [Version] = []
    private(set) var wordCount = 0
    private(set) var lastLoadMillis: Double?
    var statusLine = ""
    var conflict: Conflict?
    var isNamingTake = false

    @ObservationIgnored private var store: ProjectStore?
    @ObservationIgnored private var idleSave: Task<Void, Never>?
    @ObservationIgnored private var recount: Task<Void, Never>?
    @ObservationIgnored private var bench: Task<Void, Never>?
    /// Reads the editor's text on demand, once the editor exists.
    @ObservationIgnored private var readEditor: (() -> String?)?
    @ObservationIgnored private let log = Logger(subsystem: "com.siddharthnigam.take", category: "editor")

    static let idleSaveDelay: Duration = .seconds(10)

    init() {
        let author = Signature(name: NSFullUserName(), email: "writer@localhost")
        let folder = Self.projectFolder
        do {
            let store: ProjectStore
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
                store = try ProjectStore.open(at: folder, author: author)
            } else {
                try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
                store = try ProjectStore.create(at: folder, title: "Sample", author: author)
                let first = try store.addScene(title: "A truth universally acknowledged", toChapter: nil, text: Self.sampleText())
                let chapter = try store.manifest().chapters.first { $0.scenes.contains { $0.id == first.id } }?.id
                _ = try store.addScene(title: "Netherfield", toChapter: chapter, text: Self.netherfieldText)
            }
            self.store = store
            manuscript = try store.manifest()
            statusLine = "Opened \(folder.path)"
        } catch {
            statusLine = "Could not open the project: \(error)"
        }
        if let first = manuscript.chapters.first?.scenes.first {
            select(.main(first.id))
        }
    }

    /// The loaded text plus whatever has been typed since.
    var currentText: String {
        readEditor?() ?? editorText
    }

    var sceneTitle: String {
        selection.flatMap { manuscript.scene($0.sceneID)?.title } ?? ""
    }

    var selectionLabel: String {
        switch selection {
        case .main: return "Main"
        case .take(let take): return "Take: \(take.title)"
        case nil: return "No scene"
        }
    }

    var isInTake: Bool {
        if case .take = selection { return true }
        return false
    }

    // MARK: - Editing

    func select(_ target: Selection) {
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
            selection = target
            setEditorText(text, dirty: false)
            refresh()
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
        let text = Prose.normalize(currentText)
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
                statusLine = saved.head == take.head ? "Nothing changed on \(take.title)" : "Saved \(take.title) at \(saved.head.short)"
            }
            isDirty = false
            refresh()
        }
    }

    func restore(version: Version) {
        guard let store, let scene = selection?.sceneID else { return }
        attempt("Restore") {
            let text = try store.sceneText(scene, at: version.id)
            setEditorText(text, dirty: true)
            statusLine = "Restored \(version.id.short) into the editor, unsaved"
        }
    }

    /// The stress text as an unsaved edit.
    func loadStress() {
        setEditorText(Self.stressText, dirty: true)
        statusLine = "Stress text loaded, \(wordCount) words, unsaved"
    }

    func recordLoad(millis: Double) {
        lastLoadMillis = millis
        log.info("editor load \(millis, format: .fixed(precision: 1)) ms for \(self.wordCount) words")
    }

    // MARK: - Bench

    /// With `-TakeBench` on the command line (or the `TakeBench` default set),
    /// runs the benchmark once the editor exists, writes `bench.json` beside the
    /// project and quits, so a harness needs nothing from the UI.
    func editorReady(_ textView: ProseTextView) {
        readEditor = { [weak textView] in textView?.string }
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
            statusLine = "Started \(take.title) from \(take.base.short)"
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
                statusLine = "Kept \(take.title) as \(merge.short)"
                select(.main(take.scene))
            case .conflict(let base, let main, let mine):
                conflict = Conflict(base: base, main: main, take: mine)
                statusLine = "Main changed since \(take.title) began; nothing written"
            }
        }
    }

    func discard() {
        guard let store, case .take(let take)? = selection else { return }
        idleSave?.cancel()
        isDirty = false
        attempt("Discard") {
            try store.discard(take)
            statusLine = "Discarded \(take.title)"
            select(.main(take.scene))
        }
    }

    // MARK: - Compare

    /// In a take, the editor against main's copy of the scene. On main, the
    /// editor against the version before the current one, when there is one.
    func compare() -> ProseDiff? {
        guard let store, let selection else { return nil }
        do {
            switch selection {
            case .take(let take):
                return ProseDiffer.diff(old: try store.sceneText(take.scene), new: currentText)
            case .main(let id):
                guard history.count > 1 else { return nil }
                return ProseDiffer.diff(old: try store.sceneText(id, at: history[1].id), new: currentText)
            }
        } catch {
            statusLine = "Compare failed: \(error)"
            return nil
        }
    }

    // MARK: - Plumbing

    private func refresh() {
        guard let store else { return }
        attempt("Refresh") {
            manuscript = try store.manifest()
            guard let scene = selection?.sceneID else {
                takes = []
                history = []
                return
            }
            takes = try store.takes(for: scene)
            history = try store.history(of: scene)
            if case .take(let current)? = selection, let fresh = takes.first(where: { $0.id == current.id }) {
                selection = .take(fresh)
            }
        }
    }

    private func setEditorText(_ text: String, dirty: Bool) {
        idleSave?.cancel()
        recount?.cancel()
        editorText = text
        loadToken += 1
        isDirty = dirty
        wordCount = Prose.wordCount(text)
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
            self.wordCount = Prose.wordCount(self.currentText)
        }
    }

    private func attempt(_ what: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            statusLine = "\(what) failed: \(error)"
        }
    }

    // MARK: - Fixtures

    static var projectFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Take", isDirectory: true)
            .appendingPathComponent("Sample Project", isDirectory: true)
    }

    static let isBenchRequested = CommandLine.arguments.contains("-TakeBench") || UserDefaults.standard.bool(forKey: "TakeBench")

    static var benchFile: URL {
        projectFolder.deletingLastPathComponent().appendingPathComponent("bench.json")
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

extension Take {
    /// The slug read as a title: `take-2` shows as "Take 2".
    var title: String {
        let words = name.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
