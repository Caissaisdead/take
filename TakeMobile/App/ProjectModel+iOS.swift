import Foundation
import ManuscriptKit

/// What the phone does with a project that the Mac does differently: every
/// project lives in the app's own container under its id, and each keeps
/// its own token.
extension ProjectModel {
    // MARK: - Remembering

    nonisolated private static let lastProjectKey = "LastProjectID"

    /// Projects live under one root, so the id is enough to find one again.
    nonisolated static func remember(_ url: URL) {
        UserDefaults.standard.set(url.lastPathComponent, forKey: lastProjectKey)
    }

    /// A removed project must not come back as the last one.
    nonisolated static func forget(_ url: URL) {
        if UserDefaults.standard.string(forKey: lastProjectKey) == url.lastPathComponent {
            UserDefaults.standard.removeObject(forKey: lastProjectKey)
        }
    }

    nonisolated static func lastProjectURL() -> URL? {
        guard let id = UserDefaults.standard.string(forKey: lastProjectKey) else { return nil }
        let url = projectsRoot.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else { return nil }
        return url
    }

    /// Where the phone keeps its projects: `Application Support/Projects/<id>`.
    nonisolated static var projectsRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Projects", isDirectory: true)
    }

    // MARK: - Backup

    /// One token per project, so removing a project removes its secret.
    nonisolated static func tokenItem(for url: URL) -> KeychainItem {
        KeychainItem(service: "com.siddharthnigam.take.backup", account: url.lastPathComponent)
    }

    func backupToken() -> String? {
        projectURL.flatMap { Self.tokenItem(for: $0).read() }
    }

    /// The remote, kept per project in the defaults until the project index
    /// takes it over.
    nonisolated static func readRemote(for url: URL) -> String {
        UserDefaults.standard.string(forKey: remoteKey(url)) ?? ""
    }

    nonisolated static func writeRemote(_ remote: String, for url: URL) {
        if remote.isEmpty {
            UserDefaults.standard.removeObject(forKey: remoteKey(url))
        } else {
            UserDefaults.standard.set(remote, forKey: remoteKey(url))
        }
    }

    nonisolated private static func remoteKey(_ url: URL) -> String {
        "BackupRemote:" + url.lastPathComponent
    }
}

extension ProjectModel {
    /// A take and a milestone on the sample, once, so a posed screenshot of
    /// the map, Compare or Since has something to show. Nothing a writer
    /// would mind finding there.
    func dressSampleForPose() {
        guard milestones.isEmpty, let scene = manuscript.scenes.first else { return }
        markMilestone(named: "First draft")
        select(.main(scene.id))
        guard takes.isEmpty else { return }
        newTake(named: "Plainer")
        if case .take = selection {
            let text = Prose.editorForm("A rich single man needs a wife. Everyone says so.\n\n" + Prose.join(Array(Prose.paragraphsByLine(editorText).dropFirst())))
            setEditorText(text, dirty: true)
            save()
        }
        select(.main(scene.id))
    }
}

extension ProjectModel {
    /// What an export hands to the Files app.
    struct ExportDocument {
        let name: String
        let data: Data
        let kind: Kind
        enum Kind { case markdown, pdf }
    }

    /// The draft, or one chapter, as one Markdown file or a PDF.
    func exportDocument(_ kind: ExportDocument.Kind, chapter: UUID? = nil) -> ExportDocument? {
        guard let cut = exportCut(chapter: chapter) else { return nil }
        do {
            switch kind {
            case .markdown:
                let text = try MarkdownExport.combined(cut.manuscript, text: cut.text)
                return ExportDocument(name: cut.name, data: Data(text.utf8), kind: .markdown)
            case .pdf:
                return ExportDocument(name: cut.name, data: try PDFRenderer.data(for: cut.manuscript, text: cut.text), kind: .pdf)
            }
        } catch {
            statusLine = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }
}
