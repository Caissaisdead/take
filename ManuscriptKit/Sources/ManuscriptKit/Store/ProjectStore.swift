import Foundation

/// What the store refuses before anything reaches git.
public enum ProjectStoreError: Error, Equatable, Sendable {
    /// Main has no commit yet, so there is nothing to read.
    case unbornMain
    case unknownChapter(UUID)
    case unknownScene(SceneID)
    /// A file the manifest promises is not in the tree.
    case missingFile(String)
}

/// A writing project on disk: a folder with a git repository, `manuscript.json`
/// at the root and one Markdown file per scene. Main is checked out, so the
/// folder always reads as the current draft to any other tool. Takes are refs the
/// store reads straight from the object database; they are never checked out.
public final class ProjectStore {
    public let repository: Repository
    public var author: Signature

    public static let mainRef = "refs/heads/main"
    public static let takesPrefix = "refs/takes/"
    public static let discardedPrefix = "refs/discarded/"

    // MARK: - Opening

    /// Makes the folder, the repository, the manifest and the first commit.
    public static func create(at url: URL, title: String, author: Signature) throws -> ProjectStore {
        let store = ProjectStore(repository: try Repository.create(at: url), author: author)
        try store.writeManifest(Manuscript(title: title))
        try store.commitIndex(message: "Begin \(title)", parents: [])
        return store
    }

    public static func open(at url: URL, author: Signature) throws -> ProjectStore {
        let store = ProjectStore(repository: try Repository.open(at: url), author: author)
        // A repository without a manifest is not a project.
        _ = try store.manifest()
        return store
    }

    private init(repository: Repository, author: Signature) {
        self.repository = repository
        self.author = author
    }

    // MARK: - Manuscript

    public func manifest() throws -> Manuscript {
        try manifest(at: try mainHead())
    }

    @discardableResult
    public func saveManifest(_ manuscript: Manuscript, message: String) throws -> ObjectID {
        let head = try mainHead()
        try writeManifest(manuscript)
        return try commitIndex(message: message, parents: [head])
    }

    /// Adds a scene at the end of `chapter` (or of a first chapter made for it),
    /// writes its file and commits.
    public func addScene(title: String, toChapter chapter: UUID?, text: String) throws -> SceneRef {
        var manuscript = try manifest()
        let index: Int
        if let chapter {
            guard let found = manuscript.chapters.firstIndex(where: { $0.id == chapter }) else {
                throw ProjectStoreError.unknownChapter(chapter)
            }
            index = found
        } else {
            if manuscript.chapters.isEmpty {
                manuscript.chapters.append(Chapter(title: "Chapter 1"))
            }
            index = 0
        }

        let head = try mainHead()
        let path = try scenePath(for: title, inChapter: index, of: manuscript, at: head)
        let scene = SceneRef(id: SceneID(), title: title, path: path)
        manuscript.chapters[index].scenes.append(scene)

        try repository.writeWorkingFile(atPath: path, data: stored(text))
        try writeManifest(manuscript)
        try commitIndex(message: "Add \(title)", parents: [head])
        return scene
    }

    public func mainHead() throws -> ObjectID {
        guard let head = try repository.resolve(Self.mainRef) else { throw ProjectStoreError.unbornMain }
        return head
    }

    // MARK: - Scene text

    /// The scene as it is on main.
    public func sceneText(_ scene: SceneID) throws -> String {
        try sceneText(scene, at: try mainHead())
    }

    public func sceneText(_ scene: SceneID, at commit: ObjectID) throws -> String {
        let scene = try sceneRef(scene)
        guard let entry = try entry(scene.path, at: commit) else { throw ProjectStoreError.missingFile(scene.path) }
        return try text(of: entry.id)
    }

    /// Saves the scene on main as a checkpoint commit. Returns nil, and writes
    /// nothing, when the text's bytes equal what main already holds. The only
    /// normalisation here is a single trailing newline; paragraph shape is the
    /// caller's job.
    @discardableResult
    public func checkpoint(_ scene: SceneID, text: String, message: String? = nil) throws -> ObjectID? {
        let scene = try sceneRef(scene)
        let head = try mainHead()
        let data = stored(text)
        if let current = try entry(scene.path, at: head), try repository.readBlob(current.id) == data {
            return nil
        }
        try repository.writeWorkingFile(atPath: scene.path, data: data)
        return try commitIndex(message: message ?? "Checkpoint: \(scene.title)", parents: [head])
    }

    /// A named version of the whole draft: a commit on main with the same tree.
    @discardableResult
    public func milestone(named name: String) throws -> ObjectID {
        let head = try mainHead()
        let tree = try repository.commit(head).tree
        return try repository.createCommit(tree: tree, parents: [head], author: stamp(), message: "Milestone: \(name)", updatingRef: Self.mainRef)
    }

    /// The commits on main that changed this scene, newest first.
    public func history(of scene: SceneID, limit: Int = 50) throws -> [Version] {
        let path = try sceneRef(scene).path
        var versions: [Version] = []
        // First parents only: a take's own commits reach main through the keep
        // merge, but the keep is the version that landed.
        var commit = try repository.commit(try mainHead())
        var mine = try repository.entry(atPath: path, inTree: commit.tree)?.id
        while versions.count < limit {
            let parent = try commit.parents.first.map { try repository.commit($0) }
            let theirs = try parent.flatMap { try repository.entry(atPath: path, inTree: $0.tree)?.id }
            if let mine, mine != theirs {
                let kind: Version.Kind
                if commit.message.hasPrefix("Milestone: ") {
                    kind = .milestone
                } else if commit.parents.count == 2 {
                    kind = .keep
                } else {
                    kind = .checkpoint
                }
                versions.append(Version(id: commit.id, date: commit.author.time, message: commit.message, kind: kind))
            }
            guard let parent else { break }
            commit = parent
            mine = theirs
        }
        return versions
    }

    // MARK: - Takes

    /// Branches the scene from main's head under `refs/takes/<scene>/<slug>`. The
    /// take comes back named by its slug, as `takes(for:)` will list it.
    public func createTake(for scene: SceneID, name: String) throws -> Take {
        _ = try sceneRef(scene)
        let head = try mainHead()
        let prefix = takesPrefix(for: scene)
        let taken = Set(try repository.refs(withPrefix: prefix))
        let ref = Self.unique(prefix + Self.slug(name, fallback: "take")) { taken.contains($0) }
        try repository.updateRef(ref, to: head, message: "Take: \(name)")
        return Take(id: ref, scene: scene, name: String(ref.dropFirst(prefix.count)), base: head, head: head)
    }

    public func takes(for scene: SceneID) throws -> [Take] {
        let head = try mainHead()
        let prefix = takesPrefix(for: scene)
        var takes: [Take] = []
        for ref in try repository.refs(withPrefix: prefix) {
            guard let takeHead = try repository.resolve(ref) else { continue }
            let base = try repository.mergeBase(head, takeHead) ?? takeHead
            takes.append(Take(id: ref, scene: scene, name: String(ref.dropFirst(prefix.count)), base: base, head: takeHead))
        }
        return takes
    }

    public func takeText(_ take: Take) throws -> String {
        try sceneText(take.scene, at: take.head)
    }

    /// Commits the text on the take's ref when it changed; returns the take with
    /// its new head (or the same take when nothing changed).
    @discardableResult
    public func saveTake(_ take: Take, text: String) throws -> Take {
        let scene = try sceneRef(take.scene)
        let data = stored(text)
        let headTree = try repository.commit(take.head).tree
        if let current = try repository.entry(atPath: scene.path, inTree: headTree), try repository.readBlob(current.id) == data {
            return take
        }
        let blob = try repository.writeBlob(data)
        let tree = try repository.tree(replacing: scene.path, with: blob, in: headTree)
        let commit = try repository.createCommit(tree: tree, parents: [take.head], author: stamp(), message: "Take: \(take.name) - \(scene.title)", updatingRef: take.id)
        var saved = take
        saved.head = commit
        return saved
    }

    /// Keeps the take: when main's copy of the scene is unchanged since the take
    /// began, main gets the take's scene in a commit with two parents, the working
    /// file is updated and the take's ref is removed. A take with no commits of its
    /// own has nothing to merge, so only its ref is removed and main's head comes
    /// back. Otherwise nothing is written and the three texts come back for the
    /// writer to choose between.
    public func keep(_ take: Take) throws -> KeepResult {
        let scene = try sceneRef(take.scene)
        let head = try mainHead()
        let base = try repository.mergeBase(head, take.head) ?? take.base
        let mainTree = try repository.commit(head).tree
        let mainEntry = try repository.entry(atPath: scene.path, inTree: mainTree)
        let baseEntry = try entry(scene.path, at: base)
        guard let takeEntry = try entry(scene.path, at: take.head) else { throw ProjectStoreError.missingFile(scene.path) }

        guard mainEntry == baseEntry else {
            return .conflict(base: try text(of: baseEntry?.id), main: try text(of: mainEntry?.id), take: try text(of: takeEntry.id))
        }
        // A merge here would list main's own history as its second parent, and
        // when nothing moved at all, the same commit twice.
        if take.head == base {
            try repository.deleteRef(take.id)
            return .kept(head)
        }
        let merged = try repository.tree(replacing: scene.path, with: takeEntry.id, in: mainTree)
        let commit = try repository.createCommit(tree: merged, parents: [head, take.head], author: stamp(), message: "Keep: \(take.name) - \(scene.title)", updatingRef: Self.mainRef)
        try repository.checkoutHead()
        try repository.deleteRef(take.id)
        return .kept(commit)
    }

    /// Moves the take's ref under `refs/discarded/`, so it can be brought back.
    public func discard(_ take: Take) throws {
        let slug = take.id.split(separator: "/").last.map(String.init) ?? "take"
        let prefix = Self.discardedPrefix + take.scene.uuid.uuidString.lowercased() + "/"
        let taken = Set(try repository.refs(withPrefix: prefix))
        // A take discarded twice under one name must not overwrite the first.
        let target = Self.unique(prefix + slug) { taken.contains($0) }
        try repository.renameRef(take.id, to: target)
    }

    // MARK: - Plumbing

    private func manifest(at commit: ObjectID) throws -> Manuscript {
        guard let entry = try entry(Manuscript.manifestPath, at: commit) else {
            throw ProjectStoreError.missingFile(Manuscript.manifestPath)
        }
        return try JSONDecoder().decode(Manuscript.self, from: try repository.readBlob(entry.id))
    }

    private func writeManifest(_ manuscript: Manuscript) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(manuscript)
        data.append(0x0a)
        try repository.writeWorkingFile(atPath: Manuscript.manifestPath, data: data)
    }

    /// Commits whatever the index holds onto main.
    @discardableResult
    private func commitIndex(message: String, parents: [ObjectID]) throws -> ObjectID {
        let tree = try repository.writeIndexTree()
        return try repository.createCommit(tree: tree, parents: parents, author: stamp(), message: message, updatingRef: Self.mainRef)
    }

    /// `author` says who; each commit is stamped with the moment it is made.
    private func stamp() -> Signature {
        Signature(name: author.name, email: author.email)
    }

    private func sceneRef(_ id: SceneID) throws -> SceneRef {
        guard let scene = try manifest().scene(id) else { throw ProjectStoreError.unknownScene(id) }
        return scene
    }

    private func entry(_ path: String, at commit: ObjectID) throws -> TreeEntry? {
        try repository.entry(atPath: path, inTree: try repository.commit(commit).tree)
    }

    private func text(of blob: ObjectID?) throws -> String {
        guard let blob else { return "" }
        return String(decoding: try repository.readBlob(blob), as: UTF8.self)
    }

    /// The bytes a scene is kept as: UTF-8 ending in exactly one newline, so two
    /// saves of the same prose hash the same.
    private func stored(_ text: String) -> Data {
        var body = Substring(text)
        while let last = body.last, last == "\n" || last == "\r\n" {
            body.removeLast()
        }
        return Data((body + "\n").utf8)
    }

    private func takesPrefix(for scene: SceneID) -> String {
        Self.takesPrefix + scene.uuid.uuidString.lowercased() + "/"
    }

    /// `chapters/<NN>-<chapter slug>/<NN>-<scene slug>.md`, numbered by position
    /// in the manifest at the time the scene is added.
    private func scenePath(for title: String, inChapter index: Int, of manuscript: Manuscript, at head: ObjectID) throws -> String {
        let chapter = manuscript.chapters[index]
        let folder = "chapters/\(Self.number(index + 1))-\(Self.slug(chapter.title, fallback: "chapter"))"
        let stem = "\(Self.number(chapter.scenes.count + 1))-\(Self.slug(title, fallback: "scene"))"
        let listed = Set(manuscript.chapters.flatMap(\.scenes).map(\.path))
        let tree = try repository.commit(head).tree
        // Reordering never renames files, so a fresh number can still collide.
        let name = try Self.unique(stem) { candidate in
            let path = "\(folder)/\(candidate).md"
            return try listed.contains(path) || repository.entry(atPath: path, inTree: tree) != nil
        }
        return "\(folder)/\(name).md"
    }

    private static func number(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    /// Lowercase ASCII words joined by hyphens; anything else is stripped.
    static func slug(_ title: String, fallback: String) -> String {
        let words = title.lowercased().unicodeScalars
            .split(whereSeparator: { !($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) })
            .map { String(String.UnicodeScalarView($0)) }
        return words.isEmpty ? fallback : words.joined(separator: "-")
    }

    /// `base`, or the first of `base-2`, `base-3`… that `isTaken` accepts.
    private static func unique(_ base: String, isTaken: (String) throws -> Bool) rethrows -> String {
        var candidate = base
        var suffix = 2
        while try isTaken(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }
}
