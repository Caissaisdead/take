import Foundation
import Observation
import ManuscriptKit

/// The projects on the phone, in `Application Support/Projects/index.json`
/// beside their folders. The sample is seeded the first time the app runs,
/// so the list is never empty.
@MainActor
@Observable
final class ProjectIndex {
    private(set) var entries: [ProjectEntry] = []

    static var indexFile: URL {
        ProjectModel.projectsRoot.appendingPathComponent("index.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.indexFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([ProjectEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: ProjectModel.projectsRoot, withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: Self.indexFile, options: .atomic)
        } catch {
            // The folders are the truth; the index is rebuilt from what opens.
        }
    }

    func entry(_ id: UUID) -> ProjectEntry? {
        entries.first { $0.id == id }
    }

    func update(_ id: UUID, _ change: (inout ProjectEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
        save()
    }

    /// Takes what the open project knows into its row.
    func note(_ model: ProjectModel) {
        guard let url = model.projectURL, let id = UUID(uuidString: url.lastPathComponent) else { return }
        update(id) { entry in
            if !model.manuscript.title.isEmpty { entry.title = model.manuscript.title }
            entry.words = model.totalWords
            entry.chapters = model.manuscript.chapters.count
            if let date = model.lastBackup { entry.lastBackedUp = date }
            if let date = model.lastPull { entry.lastPulled = date }
        }
    }

    /// The first run seeds the sample, so the app never opens on nothing.
    func seedSampleIfNeeded(into model: ProjectModel) {
        guard !FileManager.default.fileExists(atPath: Self.indexFile.path) else { return }
        let entry = ProjectEntry(id: UUID(), title: "Sample Project")
        model.open(entry.folder, seedingSample: true, title: entry.title)
        guard model.projectURL == entry.folder else { return }
        entries.append(entry)
        save()
        note(model)
    }

    /// Clones the project at `remote` into a folder of its own and keeps
    /// the token with it. Blocks for the transfer off the main thread; on
    /// failure nothing is left behind.
    func clone(remote: String, token: String) async throws -> ProjectEntry {
        var entry = ProjectEntry(id: UUID(), title: "")
        let folder = entry.folder
        let author = ProjectModel.author
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: Result<String, Error> = await Task.detached {
            Result {
                try FileManager.default.createDirectory(at: ProjectModel.projectsRoot, withIntermediateDirectories: true)
                let store = try ProjectStore.clone(from: remote, to: folder, token: trimmedToken.isEmpty ? nil : trimmedToken, author: author)
                return try store.manifest().title
            }
        }.value
        switch result {
        case .success(let title):
            entry.title = title.isEmpty ? Self.name(of: remote) : title
            entry.lastPulled = Date()
            ProjectModel.writeRemote(remote, for: folder)
            if !trimmedToken.isEmpty { _ = ProjectModel.tokenItem(for: folder).write(trimmedToken) }
            entries.append(entry)
            save()
            return entry
        case .failure(let error):
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// The clone goes; the remote and the Mac keep everything. The token
    /// and the remote go with it.
    func remove(_ entry: ProjectEntry) {
        try? FileManager.default.removeItem(at: entry.folder)
        _ = ProjectModel.tokenItem(for: entry.folder).write("")
        ProjectModel.writeRemote("", for: entry.folder)
        ProjectModel.forget(entry.folder)
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// "novel" from "https://github.com/you/novel.git".
    private static func name(of remote: String) -> String {
        let last = remote.split(separator: "/").last.map(String.init) ?? remote
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }
}
