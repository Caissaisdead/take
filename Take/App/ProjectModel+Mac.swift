import AppKit
import os
import ManuscriptKit

/// What the Mac does with a project that the phone does differently: choose
/// and remember a folder outside the container, keep one token, reveal the
/// folder, run the bench, write Word and PDF through AppKit.
extension ProjectModel {
    // MARK: - Launch

    /// Bench runs and poses always use the sample; otherwise the last
    /// project, else the sample.
    func openAtLaunch() {
        if !Self.isBenchRequested, Self.shotPose == nil, let url = Self.lastProjectURL() {
            open(url)
        }
        if projectURL == nil {
            openSample()
        }
    }

    /// The notice is posted on the main thread, before any window goes, so
    /// the save runs whole.
    func installTerminationSave() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveBeforeLeaving()
            }
        }
    }

    func openSample() {
        open(Self.sampleFolder, seedingSample: true)
    }

    // MARK: - Projects

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

    /// Reads a manuscript from a file or a folder into a new project, or takes
    /// in a project folder that has its manifest but no repository.
    func importProject() {
        guard !isWritingTakes else {
            statusLine = "Three Takes is still writing; stop it before importing"
            return
        }
        Task {
            guard let source = await ProjectPanels.chooseImport() else { return }
            let granted = source.startAccessingSecurityScopedResource()
            defer { if granted { source.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: source.appendingPathComponent(Manuscript.manifestPath).path),
               !FileManager.default.fileExists(atPath: source.appendingPathComponent(".git").path) {
                adopt(source)
                return
            }
            let draft: Draft
            do {
                draft = try ManuscriptReader.draft(from: source)
            } catch {
                statusLine = "Import failed: \(error.localizedDescription)"
                return
            }
            let counts = "\(draft.chapters.count) \(draft.chapters.count == 1 ? "chapter" : "chapters"), \(draft.scenes.count) \(draft.scenes.count == 1 ? "scene" : "scenes")"
            guard let url = await ProjectPanels.chooseNewProjectFolder(named: draft.title, message: "\(counts) read from \(source.lastPathComponent). The folder becomes the project.") else { return }
            settle()
            guard !isDirty else { return }
            guard Self.isEmptyFolder(url) else {
                statusLine = "\(url.lastPathComponent) has files in it; choose an empty folder"
                return
            }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                _ = try ProjectStore.create(at: url, draft: draft, author: Self.author)
            } catch {
                statusLine = "Import failed: \(error.localizedDescription)"
                return
            }
            open(url)
            statusLine = "Imported \(counts) into \(url.lastPathComponent)"
        }
    }

    /// A project folder without its repository becomes one again, in place.
    private func adopt(_ url: URL) {
        settle()
        guard !isDirty else { return }
        do {
            _ = try ProjectStore.adopt(at: url, author: Self.author)
        } catch {
            statusLine = "Could not take in \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }
        open(url)
        statusLine = "Took in \(url.lastPathComponent) as a project"
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

    // MARK: - Remembering

    private static let bookmarkKey = "LastProjectBookmark"

    static func remember(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    /// The last project's folder, when it still holds a repository. The sandbox
    /// answers nothing about a folder outside the container until its grant is
    /// taken up, so the check runs inside one; `open` takes its own, and
    /// `remember` renews a bookmark that has gone stale.
    static func lastProjectURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else { return nil }
        return url
    }

    // MARK: - Backup

    /// The Mac keeps one token for every project.
    func backupToken() -> String? {
        KeychainItem.backupToken.read()
    }

    /// The remote, kept per project folder in the defaults.
    static func readRemote(for url: URL) -> String {
        UserDefaults.standard.string(forKey: backupKey(url)) ?? ""
    }

    static func writeRemote(_ remote: String, for url: URL) {
        if remote.isEmpty {
            UserDefaults.standard.removeObject(forKey: backupKey(url))
        } else {
            UserDefaults.standard.set(remote, forKey: backupKey(url))
        }
    }

    private static func backupKey(_ url: URL) -> String {
        "BackupRemote:" + url.standardizedFileURL.path
    }

    // MARK: - Export

    enum ExportKind { case markdown, docx, pdf }

    /// The draft on main, or one chapter of it, as a folder of Markdown, a
    /// Word document or a PDF.
    func export(_ kind: ExportKind, chapter: UUID? = nil) {
        guard let cut = exportCut(chapter: chapter) else { return }
        do {
            switch kind {
            case .markdown:
                let files = try cut.markdown()
                Task { await finish("Exported \(files.count) files") { try await ExportCoordinator.exportMarkdown(files, suggestedName: cut.name) } }
            case .docx:
                let data = try DocxWriter.data(for: cut.manuscript, text: cut.text)
                Task { await finish("Exported") { try await ExportCoordinator.exportDocx(data, suggestedName: cut.name) } }
            case .pdf:
                let data = try PDFWriter.data(for: cut.manuscript, text: cut.text)
                Task { await finish("Exported") { try await ExportCoordinator.exportPDF(data, suggestedName: cut.name) } }
            }
        } catch {
            statusLine = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Runs the save panel and reports where the export went, or why not.
    private func finish(_ verb: String, _ save: () async throws -> URL?) async {
        do {
            if let url = try await save() {
                statusLine = "\(verb) to \(url.lastPathComponent)"
            }
        } catch {
            statusLine = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Bench

    /// The editor is up: wire it to the model and, with `-TakeBench` on the
    /// command line (or the `TakeBench` default set), run the benchmark once,
    /// write `bench.json` beside the project and quit, so a harness needs
    /// nothing from the UI.
    func editorReady(_ textView: ProseTextView) {
        editorReady(textView as any EditorHost)
        guard Self.isBenchRequested, !Self.benchStarted else { return }
        Self.benchStarted = true
        Task { await runBench(on: textView) }
    }

    /// The stress text in the editor, for the bench alone. Not marked dirty,
    /// so the idle save never commits it over the scene; only a save the
    /// writer asks for does.
    func loadStress() {
        setEditorText(Prose.editorForm(Self.stressText), dirty: false)
        statusLine = "Stress text loaded, \(wordCount) words; Save would commit it"
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
        let log = Logger(subsystem: "com.siddharthnigam.take", category: "bench")
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
        abandonEdits()
        NSApp.terminate(nil)
    }

    @MainActor private static var benchStarted = false

    static let isBenchRequested = CommandLine.arguments.contains("-TakeBench") || UserDefaults.standard.bool(forKey: "TakeBench")

    // MARK: - Fixtures

    /// The seeded sample, in the app's own container.
    static var sampleFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Take", isDirectory: true)
            .appendingPathComponent("Sample Project", isDirectory: true)
    }

    static var benchFile: URL {
        sampleFolder.deletingLastPathComponent().appendingPathComponent("bench.json")
    }

    /// The sample scene four times over: about 20k words.
    static var stressText: String {
        let block = sampleText().trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(repeating: block, count: 4).joined(separator: "\n\n") + "\n"
    }
}
