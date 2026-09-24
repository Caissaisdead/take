import Foundation

/// What the store refuses before anything reaches git.
public enum ProjectStoreError: Error, Equatable, Sendable, LocalizedError {
    /// Main has no commit yet, so there is nothing to read.
    case unbornMain
    /// The manifest was written by a different version of the code.
    case unsupportedFormat(Int)
    case unknownPart(UUID)
    case unknownChapter(UUID)
    case unknownScene(SceneID)
    /// A file the manifest promises is not in the tree.
    case missingFile(String)
    /// A scene with this identity is in the manuscript already.
    case duplicateScene(SceneID)

    public var errorDescription: String? {
        switch self {
        case .unbornMain:
            return "The repository has no commit on main yet."
        case .unsupportedFormat(let format):
            return format > Manuscript.currentFormat
                ? "This manuscript was written by a newer version of Take (format \(format))."
                : "This manuscript is in an older form (format \(format)) that this version of Take does not read."
        case .unknownPart:
            return "That part is not in the manuscript."
        case .unknownChapter:
            return "That chapter is not in the manuscript."
        case .unknownScene:
            return "That scene is not in the manuscript."
        case .missingFile(let path):
            return path == Manuscript.manifestPath
                ? "The folder's repository has no \(path), so it is not a Take project."
                : "The manuscript names \(path), but the file is not in the draft."
        case .duplicateScene:
            return "That scene is in the manuscript already."
        }
    }
}

/// A writing project on disk: a folder with a git repository, `manuscript.json`
/// at the root and one Markdown file per scene. Main is checked out, so the
/// folder always reads as the current draft to any other tool. Takes are refs the
/// store reads straight from the object database; they are never checked out.
public final class ProjectStore {
    public let repository: Repository
    public var author: Signature
    /// The moment a commit is stamped with; the clock, unless a test says otherwise.
    public var clock: () -> Date = { Date() }

    public static let mainRef = "refs/heads/main"
    public static let takesPrefix = "refs/takes/"
    public static let discardedPrefix = "refs/discarded/"
    public static let milestonesPrefix = "refs/tags/milestones/"

    /// The manifest as decoded from main's head, kept until the head moves.
    /// Nearly every call reads it, and the app reads it after every save.
    private var cachedManifest: (head: ObjectID, manuscript: Manuscript)?
    /// Each scene's history as read from the head it was read at, and whether
    /// that read ran back to the root. A later read walks only the commits
    /// since, then goes on with what it had.
    private var historyCache: [SceneID: (head: ObjectID, versions: [Version], exhausted: Bool)] = [:]
    /// Scenes found removed, walking back from the head they were read at.
    private var removedCache: (head: ObjectID, found: [RemovedScene])?
    /// Words per blob, so a refresh counts only the scene that changed.
    private var wordsByBlob: [ObjectID: Int] = [:]
    /// The commit a day began at, found once per day.
    private var dayStart: (day: Date, commit: ObjectID?)?

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

    init(repository: Repository, author: Signature) {
        self.repository = repository
        self.author = author
    }

    // MARK: - Manuscript

    public func manifest() throws -> Manuscript {
        let head = try mainHead()
        if let cached = cachedManifest, cached.head == head { return cached.manuscript }
        let manuscript = try manifest(at: head)
        cachedManifest = (head, manuscript)
        return manuscript
    }

    @discardableResult
    public func saveManifest(_ manuscript: Manuscript, message: String) throws -> ObjectID {
        let head = try mainHead()
        try writeManifest(manuscript)
        return try commitIndex(message: message, parents: [head])
    }

    // MARK: - Shape

    /// Adds a part at the end and commits.
    public func addPart(title: String) throws -> Part {
        var manuscript = try manifest()
        let part = Part(title: title)
        manuscript.append(part)
        try saveManifest(manuscript, message: "Add part \(Self.label(title))")
        return part
    }

    /// Adds a chapter at the end of `part` (or of the last part, or of an
    /// untitled part made for it) and commits. The chapter's folder is fixed
    /// here, from its title and its number among all chapters.
    public func addChapter(title: String, toPart part: UUID?) throws -> Chapter {
        var manuscript = try manifest()
        let chapter = try newChapter(title: title, in: &manuscript)
        try manuscript.append(chapter, toPart: try Self.destinationPart(part, in: &manuscript))
        try saveManifest(manuscript, message: "Add chapter \(Self.label(title))")
        return chapter
    }

    /// Adds a scene to `chapter` (or to the last chapter, or to a first chapter
    /// made for it) at `index` among its scenes or at the end, writes its file
    /// and commits. A restored scene brings its old identity, so its takes
    /// answer to it again.
    public func addScene(title: String, toChapter chapter: UUID?, at index: Int? = nil, text: String, id: SceneID = SceneID(), synopsis: String = "", notes: String = "", message: String? = nil) throws -> SceneRef {
        var manuscript = try manifest()
        let head = try mainHead()
        guard manuscript.scene(id) == nil else { throw ProjectStoreError.duplicateScene(id) }
        let destination: UUID
        if let chapter {
            guard manuscript.chapter(chapter) != nil else { throw ProjectStoreError.unknownChapter(chapter) }
            destination = chapter
        } else if let last = manuscript.chapters.last {
            destination = last.id
        } else {
            let first = try newChapter(title: "Chapter 1", in: &manuscript)
            try manuscript.append(first, toPart: try Self.destinationPart(nil, in: &manuscript))
            destination = first.id
        }
        let path = try scenePath(for: title, in: manuscript.chapter(destination)!, of: manuscript, at: head)
        let scene = SceneRef(id: id, title: title, path: path, synopsis: synopsis, notes: notes)
        try manuscript.insert(scene, inChapter: destination, at: index)

        try repository.writeWorkingFile(atPath: path, data: stored(text))
        try writeManifest(manuscript)
        try commitIndex(message: message ?? "Add \(Self.label(title))", parents: [head])
        return scene
    }

    // MARK: - Removed scenes

    /// Scenes taken out of the manuscript and not in it now, most recently
    /// removed first, found by walking main's first parents and comparing
    /// each manifest with the one before it. Read from the head last read at,
    /// like history, so a refresh walks only the commits since.
    public func removedScenes(limit: Int = 200) throws -> [RemovedScene] {
        let head = try mainHead()
        let present = Set(try manifest().scenes.map(\.id))
        if let cached = removedCache, cached.head == head {
            return cached.found.filter { !present.contains($0.scene.id) }
        }
        var found: [RemovedScene] = []
        var commit = try repository.commit(head)
        var manuscript = try manifest(at: head)
        var steps = 0
        while steps < limit {
            if let cached = removedCache, commit.id == cached.head {
                found.append(contentsOf: cached.found)
                break
            }
            guard let parentID = commit.parents.first else { break }
            let parent = try repository.commit(parentID)
            let older = try manifest(at: parentID)
            let kept = Set(manuscript.scenes.map(\.id))
            for chapter in older.chapters {
                for scene in chapter.scenes where !kept.contains(scene.id) {
                    found.append(RemovedScene(scene: scene, chapter: chapter.id, chapterTitle: chapter.title, removedAt: commit.id, before: parentID, date: commit.author.time))
                }
            }
            commit = parent
            manuscript = older
            steps += 1
        }
        // A scene removed twice is listed once, as it last was.
        var seen: Set<SceneID> = []
        found = found.filter { seen.insert($0.scene.id).inserted }
        removedCache = (head, found)
        return found.filter { !present.contains($0.scene.id) }
    }

    /// Puts a removed scene back with its old identity, text, synopsis and
    /// notes: at the end of the chapter it was in, when that is still there,
    /// or of the last chapter. Its takes are listed again by that alone.
    @discardableResult
    public func restore(removed: RemovedScene) throws -> SceneRef {
        guard let entry = try entry(removed.scene.path, at: removed.before) else { throw ProjectStoreError.missingFile(removed.scene.path) }
        let text = try text(of: entry.id)
        let chapter = try manifest().chapter(removed.chapter)?.id
        return try addScene(
            title: removed.scene.title, toChapter: chapter, text: text,
            id: removed.scene.id, synopsis: removed.scene.synopsis, notes: removed.scene.notes,
            message: "Restore \(Self.label(removed.scene.title))")
    }

    public func rename(part id: UUID, to title: String) throws {
        var manuscript = try manifest()
        let old = try Self.require(manuscript.part(id), ProjectStoreError.unknownPart(id)).title
        try manuscript.rename(part: id, to: title)
        try saveManifest(manuscript, message: "Rename part \(Self.label(old)) to \(Self.label(title))")
    }

    public func rename(chapter id: UUID, to title: String) throws {
        var manuscript = try manifest()
        let old = try Self.require(manuscript.chapter(id), ProjectStoreError.unknownChapter(id)).title
        try manuscript.rename(chapter: id, to: title)
        try saveManifest(manuscript, message: "Rename chapter \(Self.label(old)) to \(Self.label(title))")
    }

    /// The scene's synopsis and notes, in the manifest and so in history.
    public func update(scene id: SceneID, synopsis: String, notes: String) throws {
        var manuscript = try manifest()
        let scene = try sceneRef(id)
        guard scene.synopsis != synopsis || scene.notes != notes else { return }
        try manuscript.set(synopsis: synopsis, notes: notes, forScene: id)
        try saveManifest(manuscript, message: "Note \(Self.label(scene.title))")
    }

    /// The draft's word target and the day's, nil to clear either.
    public func setTargets(_ target: Int?, daily: Int?) throws {
        var manuscript = try manifest()
        guard manuscript.target != target || manuscript.dailyTarget != daily else { return }
        manuscript.target = target
        manuscript.dailyTarget = daily
        try saveManifest(manuscript, message: "Set target")
    }

    /// The file keeps its name; only the manifest changes.
    public func rename(scene id: SceneID, to title: String) throws {
        var manuscript = try manifest()
        let old = try sceneRef(id).title
        try manuscript.rename(scene: id, to: title)
        try saveManifest(manuscript, message: "Rename \(Self.label(old)) to \(Self.label(title))")
    }

    /// Moves never touch files: order is the manifest's alone.
    public func move(scene id: SceneID, toChapter chapter: UUID, at index: Int) throws {
        var manuscript = try manifest()
        let title = try sceneRef(id).title
        try manuscript.move(scene: id, toChapter: chapter, at: index)
        try saveManifest(manuscript, message: "Move \(Self.label(title))")
    }

    public func move(chapter id: UUID, toPart part: UUID, at index: Int) throws {
        var manuscript = try manifest()
        let title = try Self.require(manuscript.chapter(id), ProjectStoreError.unknownChapter(id)).title
        try manuscript.move(chapter: id, toPart: part, at: index)
        try saveManifest(manuscript, message: "Move chapter \(Self.label(title))")
    }

    public func move(part id: UUID, to index: Int) throws {
        var manuscript = try manifest()
        let title = try Self.require(manuscript.part(id), ProjectStoreError.unknownPart(id)).title
        try manuscript.move(part: id, to: index)
        try saveManifest(manuscript, message: "Move part \(Self.label(title))")
    }

    /// Takes the scene out of the manifest and its file out of the tree. The
    /// text stays in history, and any takes on it keep their refs.
    public func remove(scene id: SceneID) throws {
        var manuscript = try manifest()
        let head = try mainHead()
        let scene = try manuscript.remove(scene: id)
        try repository.removeWorkingFile(atPath: scene.path)
        try writeManifest(manuscript)
        try commitIndex(message: "Remove \(Self.label(scene.title))", parents: [head])
    }

    /// The chapter and every scene in it, in one commit.
    public func remove(chapter id: UUID) throws {
        var manuscript = try manifest()
        let head = try mainHead()
        let chapter = try manuscript.remove(chapter: id)
        for scene in chapter.scenes {
            try repository.removeWorkingFile(atPath: scene.path)
        }
        try writeManifest(manuscript)
        try commitIndex(message: "Remove chapter \(Self.label(chapter.title))", parents: [head])
    }

    /// The part and everything under it, in one commit.
    public func remove(part id: UUID) throws {
        var manuscript = try manifest()
        let head = try mainHead()
        let part = try manuscript.remove(part: id)
        for scene in part.chapters.flatMap(\.scenes) {
            try repository.removeWorkingFile(atPath: scene.path)
        }
        try writeManifest(manuscript)
        try commitIndex(message: "Remove part \(Self.label(part.title))", parents: [head])
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

    /// Marks main's head as a milestone: an annotated tag, so the draft itself
    /// gains no commit. The tag carries the name as given; the ref is slugged
    /// and made unique.
    @discardableResult
    public func milestone(named name: String) throws -> Milestone {
        let head = try mainHead()
        let taken = Set(try repository.refs(withPrefix: Self.milestonesPrefix))
        let ref = Self.unique(Self.milestonesPrefix + Self.slug(name, fallback: "milestone")) { taken.contains($0) }
        let tag = try repository.createTag(String(ref.dropFirst("refs/tags/".count)), target: head, tagger: stamp(), message: name)
        let info = try repository.tag(tag)
        return Milestone(id: ref, name: name, commit: head, date: info.tagger.time)
    }

    /// Every milestone, newest first.
    public func milestones() throws -> [Milestone] {
        var milestones: [Milestone] = []
        for ref in try repository.refs(withPrefix: Self.milestonesPrefix) {
            guard let id = try repository.resolve(ref) else { continue }
            let tag = try repository.tag(id)
            let name = tag.message.trimmingCharacters(in: .whitespacesAndNewlines)
            milestones.append(Milestone(id: ref, name: name.isEmpty ? tag.name : name, commit: tag.target, date: tag.tagger.time))
        }
        // Two in the same second fall back to their refs, so a `-2` follows its original.
        return milestones.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    /// The commits on main that changed this scene, newest first.
    public func history(of scene: SceneID, limit: Int = 50) throws -> [Version] {
        let path = try sceneRef(scene).path
        let head = try mainHead()
        let cached = historyCache[scene]
        if let cached, cached.head == head, cached.exhausted || cached.versions.count >= limit {
            return Array(cached.versions.prefix(limit))
        }
        var versions: [Version] = []
        var exhausted = false
        // First parents only: a take's own commits reach main through the keep
        // merge, but the keep is the version that landed.
        var commit = try repository.commit(head)
        var mine = try repository.entry(atPath: path, inTree: commit.tree)?.id
        while versions.count < limit {
            // Back at the head last read from: what follows is already known,
            // unless that read stopped short of what is asked for now.
            if let cached, commit.id == cached.head, cached.exhausted || versions.count + cached.versions.count >= limit {
                versions.append(contentsOf: cached.versions)
                exhausted = cached.exhausted
                break
            }
            let parent = try commit.parents.first.map { try repository.commit($0) }
            let theirs = try parent.flatMap { try repository.entry(atPath: path, inTree: $0.tree)?.id }
            if let mine, mine != theirs {
                let kind: Version.Kind = commit.parents.count == 2 ? .keep : .checkpoint
                versions.append(Version(id: commit.id, date: commit.author.time, message: commit.message, kind: kind))
            }
            guard let parent else {
                exhausted = true
                break
            }
            commit = parent
            mine = theirs
        }
        historyCache[scene] = (head, versions, exhausted)
        return Array(versions.prefix(limit))
    }

    // MARK: - Backup

    /// Everything a backup carries: main, the milestones, the takes and the
    /// discarded takes. Main is not forced, so a remote that has moved on is
    /// reported rather than overwritten.
    public static let backupRefspecs = [
        "refs/heads/main:refs/heads/main",
        "refs/tags/milestones/*:refs/tags/milestones/*",
        "refs/takes/*:refs/takes/*",
        "refs/discarded/*:refs/discarded/*",
    ]

    /// Pushes the project to `url`. Opens its own repository so it can run
    /// on any thread while the store's own stays where it is.
    public static func backUp(projectAt folder: URL, to url: String, token: String?) throws {
        try Repository.open(at: folder).push(to: url, refspecs: backupRefspecs, token: token)
    }

    // MARK: - Since

    /// Every scene against how the draft stood at `commit`: the words added
    /// and removed since, in manuscript order, with the scenes gone since
    /// listed last in their old order. A scene that moved or was renamed but
    /// whose text did not change reads as the same.
    public func changes(since commit: ObjectID) throws -> [SceneChange] {
        let now = try manifest()
        let then = try manifest(at: commit)
        let oldTree = try repository.commit(commit).tree
        let newTree = try repository.commit(try mainHead()).tree
        let thenScenes = Set(then.scenes.map(\.id))
        var changes: [SceneChange] = []
        for chapter in now.chapters {
            for scene in chapter.scenes {
                let newEntry = try repository.entry(atPath: scene.path, inTree: newTree)
                let newText = try text(of: newEntry?.id)
                guard thenScenes.contains(scene.id) else {
                    changes.append(SceneChange(scene: scene, chapter: chapter.id, kind: .added, wordsAdded: Prose.wordCount(Prose.withoutNotes(newText)), wordsRemoved: 0))
                    continue
                }
                let oldEntry = try repository.entry(atPath: scene.path, inTree: oldTree)
                if oldEntry?.id == newEntry?.id {
                    changes.append(SceneChange(scene: scene, chapter: chapter.id, kind: .same, wordsAdded: 0, wordsRemoved: 0))
                    continue
                }
                let summary = ProseDiffer.diff(old: Prose.withoutNotes(try text(of: oldEntry?.id)), new: Prose.withoutNotes(newText)).summary
                let kind: SceneChange.Kind = summary.paragraphsChanged == 0 ? .same : .changed
                changes.append(SceneChange(scene: scene, chapter: chapter.id, kind: kind, wordsAdded: summary.wordsAdded, wordsRemoved: summary.wordsRemoved))
            }
        }
        let nowScenes = Set(now.scenes.map(\.id))
        for chapter in then.chapters {
            for scene in chapter.scenes where !nowScenes.contains(scene.id) {
                let oldEntry = try repository.entry(atPath: scene.path, inTree: oldTree)
                let words = Prose.wordCount(Prose.withoutNotes(try text(of: oldEntry?.id)))
                changes.append(SceneChange(scene: scene, chapter: chapter.id, kind: .removed, wordsAdded: 0, wordsRemoved: words))
            }
        }
        return changes
    }

    // MARK: - Counting

    /// Words per scene, notes left out, at `commit` or at main's head.
    public func wordCounts(at commit: ObjectID? = nil) throws -> [SceneID: Int] {
        let at = try commit ?? mainHead()
        let tree = try repository.commit(at).tree
        var counts: [SceneID: Int] = [:]
        for scene in try manifest(at: at).scenes {
            guard let entry = try repository.entry(atPath: scene.path, inTree: tree) else { continue }
            if let known = wordsByBlob[entry.id] {
                counts[scene.id] = known
            } else {
                let words = Prose.wordCount(Prose.withoutNotes(try text(of: entry.id)))
                wordsByBlob[entry.id] = words
                counts[scene.id] = words
            }
        }
        return counts
    }

    /// The draft's words as `day` began: at the last commit on main made
    /// before that day's midnight, or nil when the whole draft is younger.
    public func wordCountAtStart(of day: Date, calendar: Calendar = .current) throws -> Int? {
        let midnight = calendar.startOfDay(for: day)
        let head = try mainHead()
        let start: ObjectID?
        if let dayStart, dayStart.day == midnight {
            start = dayStart.commit
        } else {
            var commit: CommitInfo? = try repository.commit(head)
            while let c = commit, c.author.time >= midnight {
                commit = try c.parents.first.map { try repository.commit($0) }
            }
            start = commit?.id
            dayStart = (midnight, start)
        }
        guard let start else { return nil }
        return try wordCounts(at: start).values.reduce(0, +)
    }

    // MARK: - Export

    /// The draft on main as Markdown files, combined draft first; or one
    /// chapter of it.
    public func exportMarkdown(chapter: UUID? = nil) throws -> [ExportFile] {
        let manuscript = try manifest(chapter: chapter)
        let head = try mainHead()
        return try MarkdownExport.files(for: manuscript) { try sceneText($0, at: head) }
    }

    /// The manifest, or the one chapter of it that an export asks for.
    public func manifest(chapter: UUID?) throws -> Manuscript {
        let whole = try manifest()
        guard let chapter else { return whole }
        guard let cut = whole.only(chapter: chapter) else { throw ProjectStoreError.unknownChapter(chapter) }
        return cut
    }

    // MARK: - Takes

    /// Branches the scene from main's head under `refs/takes/<scene>/<name>`.
    /// The ref carries the name itself, percent-encoded where git forbids a
    /// character, so a take reads back exactly as it was named. A name already
    /// in use (in any case) gets a number.
    public func createTake(for scene: SceneID, name: String) throws -> Take {
        _ = try sceneRef(scene)
        let head = try mainHead()
        let prefix = takesPrefix(for: scene)
        let taken = Set(try repository.refs(withPrefix: prefix).map { $0.lowercased() })
        let given = Self.takeName(name)
        var candidate = given
        var suffix = 2
        while taken.contains((prefix + Self.refComponent(candidate)).lowercased()) {
            candidate = "\(given) \(suffix)"
            suffix += 1
        }
        let ref = prefix + Self.refComponent(candidate)
        try repository.updateRef(ref, to: head, message: "Take: \(candidate)")
        return Take(id: ref, scene: scene, name: candidate, base: head, head: head)
    }

    public func takes(for scene: SceneID) throws -> [Take] {
        let head = try mainHead()
        let prefix = takesPrefix(for: scene)
        var takes: [Take] = []
        for ref in try repository.refs(withPrefix: prefix) {
            guard let takeHead = try repository.resolve(ref) else { continue }
            let base = try repository.mergeBase(head, takeHead) ?? takeHead
            takes.append(Take(id: ref, scene: scene, name: Self.takeName(fromRef: ref, prefix: prefix), base: base, head: takeHead))
        }
        return takes
    }

    /// Takes discarded from this scene, under `refs/discarded/`, by name.
    /// Their base is the merge base with main today, as for live takes.
    public func discardedTakes(for scene: SceneID) throws -> [Take] {
        let head = try mainHead()
        let prefix = Self.discardedPrefix + scene.uuid.uuidString.lowercased() + "/"
        var takes: [Take] = []
        for ref in try repository.refs(withPrefix: prefix) {
            guard let takeHead = try repository.resolve(ref) else { continue }
            let base = try repository.mergeBase(head, takeHead) ?? takeHead
            takes.append(Take(id: ref, scene: scene, name: Self.takeName(fromRef: ref, prefix: prefix), base: base, head: takeHead))
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
    /// began, main gets the take's scene in a commit with two parents, the scene's
    /// working file alone is rewritten and the take's ref is removed. A take with
    /// no commits of its own has nothing to merge, so only its ref is removed and
    /// main's head comes back. Otherwise nothing is written and the three texts
    /// come back for the writer to choose between.
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
        // Only this file: anything else changed on disk by another tool is
        // the writer's, not ours to reset.
        try repository.writeWorkingFile(atPath: scene.path, data: try repository.readBlob(takeEntry.id))
        try repository.deleteRef(take.id)
        return .kept(commit)
    }

    /// Settles a keep that met a moved main, whole scene one way or the other.
    /// Either way main gets a commit with the take as its second parent, so the
    /// history says the take was weighed, and the take's ref is removed.
    /// `.take` puts the take's text on main; `.main` leaves main's text as it is.
    @discardableResult
    public func keep(_ take: Take, choosing side: KeepSide) throws -> ObjectID {
        let scene = try sceneRef(take.scene)
        let head = try mainHead()
        let mainTree = try repository.commit(head).tree
        let tree: ObjectID
        let verb: String
        var written: ObjectID?
        switch side {
        case .take:
            guard let takeEntry = try entry(scene.path, at: take.head) else { throw ProjectStoreError.missingFile(scene.path) }
            tree = try repository.tree(replacing: scene.path, with: takeEntry.id, in: mainTree)
            verb = "Keep"
            written = takeEntry.id
        case .main:
            tree = mainTree
            verb = "Keep main over"
        }
        let commit = try repository.createCommit(tree: tree, parents: [head, take.head], author: stamp(), message: "\(verb): \(take.name) - \(scene.title)", updatingRef: Self.mainRef)
        if let written {
            try repository.writeWorkingFile(atPath: scene.path, data: try repository.readBlob(written))
        }
        try repository.deleteRef(take.id)
        return commit
    }

    /// Moves the take's ref under `refs/discarded/`, so it can be brought back.
    public func discard(_ take: Take) throws {
        let prefix = Self.discardedPrefix + take.scene.uuid.uuidString.lowercased() + "/"
        try repository.renameRef(take.id, to: try freeRef(named: take.name, under: prefix))
    }

    /// Brings a discarded take back under `refs/takes/`, numbered if its name
    /// has since been reused. Returns the take as `takes(for:)` will list it.
    @discardableResult
    public func restore(discarded take: Take) throws -> Take {
        let prefix = takesPrefix(for: take.scene)
        let ref = try freeRef(named: take.name, under: prefix)
        try repository.renameRef(take.id, to: ref)
        let head = try mainHead()
        let base = try repository.mergeBase(head, take.head) ?? take.head
        return Take(id: ref, scene: take.scene, name: Self.takeName(fromRef: ref, prefix: prefix), base: base, head: take.head)
    }

    /// A ref under `prefix` for `name`, numbered past any already there. A take
    /// discarded twice under one name must not overwrite the first.
    private func freeRef(named name: String, under prefix: String) throws -> String {
        let taken = Set(try repository.refs(withPrefix: prefix).map { $0.lowercased() })
        var candidate = name
        var suffix = 2
        while taken.contains((prefix + Self.refComponent(candidate)).lowercased()) {
            candidate = "\(name) \(suffix)"
            suffix += 1
        }
        return prefix + Self.refComponent(candidate)
    }

    // MARK: - Plumbing

    private func manifest(at commit: ObjectID) throws -> Manuscript {
        guard let entry = try entry(Manuscript.manifestPath, at: commit) else {
            throw ProjectStoreError.missingFile(Manuscript.manifestPath)
        }
        let data = try repository.readBlob(entry.id)
        // The format is checked on its own first, so an older manifest says so
        // instead of failing on whatever key it lacks.
        struct Stamp: Decodable { var format: Int? }
        let format = try JSONDecoder().decode(Stamp.self, from: data).format ?? 1
        guard Manuscript.readableFormats.contains(format) else { throw ProjectStoreError.unsupportedFormat(format) }
        var manuscript = try JSONDecoder().decode(Manuscript.self, from: data)
        // An older shape reads with its missing fields empty and is written
        // back in the current shape by the next commit.
        manuscript.format = Manuscript.currentFormat
        return manuscript
    }

    func writeManifest(_ manuscript: Manuscript) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(manuscript)
        data.append(0x0a)
        try repository.writeWorkingFile(atPath: Manuscript.manifestPath, data: data)
    }

    /// Commits whatever the index holds onto main.
    @discardableResult
    func commitIndex(message: String, parents: [ObjectID]) throws -> ObjectID {
        let tree = try repository.writeIndexTree()
        return try repository.createCommit(tree: tree, parents: parents, author: stamp(), message: message, updatingRef: Self.mainRef)
    }

    /// `author` says who; each commit is stamped with the moment it is made.
    private func stamp() -> Signature {
        Signature(name: author.name, email: author.email, time: clock())
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
    func stored(_ text: String) -> Data {
        var body = Substring(text)
        while let last = body.last, last == "\n" || last == "\r\n" {
            body.removeLast()
        }
        return Data((body + "\n").utf8)
    }

    private func takesPrefix(for scene: SceneID) -> String {
        Self.takesPrefix + scene.uuid.uuidString.lowercased() + "/"
    }

    /// A chapter with its folder fixed: `chapters/<NN>-<slug>`, numbered by how
    /// many chapters the manuscript has had before it. Chapters are numbered
    /// across parts, so the folder never says which part it is in.
    func newChapter(title: String, in manuscript: inout Manuscript) throws -> Chapter {
        let stem = "chapters/\(number(manuscript.chapters.count + 1))-\(Self.slug(title, fallback: "chapter"))"
        let used = Set(manuscript.chapters.map(\.folder))
        let tree = try repository.commit(try mainHead()).tree
        // A removed chapter's folder is gone from the tree with its scenes, but
        // a reordered one keeps its number, so a fresh number can still collide.
        let folder = try Self.unique(stem) { candidate in
            try used.contains(candidate) || repository.entry(atPath: candidate, inTree: tree) != nil
        }
        return Chapter(title: title, folder: folder)
    }

    /// `part` itself, or the last part, or an untitled part appended for the
    /// purpose.
    static func destinationPart(_ part: UUID?, in manuscript: inout Manuscript) throws -> UUID {
        if let part {
            guard manuscript.part(part) != nil else { throw ProjectStoreError.unknownPart(part) }
            return part
        }
        if let last = manuscript.parts.last { return last.id }
        let made = Part(title: "")
        manuscript.append(made)
        return made.id
    }

    /// `<chapter folder>/<NN>-<scene slug>.md`, numbered by the chapter's scene
    /// count at the time the scene is added.
    func scenePath(for title: String, in chapter: Chapter, of manuscript: Manuscript, at head: ObjectID) throws -> String {
        let stem = "\(number(chapter.scenes.count + 1))-\(Self.slug(title, fallback: "scene"))"
        let listed = Set(manuscript.scenes.map(\.path))
        let tree = try repository.commit(head).tree
        // Reordering never renames files, so a fresh number can still collide.
        let name = try Self.unique(stem) { candidate in
            let path = "\(chapter.folder)/\(candidate).md"
            return try listed.contains(path) || repository.entry(atPath: path, inTree: tree) != nil
        }
        return "\(chapter.folder)/\(name).md"
    }

    /// A title as a commit message shows it; an empty one reads as untitled.
    static func label(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(untitled)" : trimmed
    }

    private static func require<T>(_ value: T?, _ error: ProjectStoreError) throws -> T {
        guard let value else { throw error }
        return value
    }


    /// A take's name as given, trimmed; an empty name is "Take".
    static func takeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Take" : trimmed
    }

    static func takeName(fromRef ref: String, prefix: String) -> String {
        let component = String(ref.dropFirst(prefix.count))
        return component.removingPercentEncoding ?? component
    }

    /// The name as one component of a ref: letters, digits, hyphens and
    /// underscores as they are, every other character as its UTF-8 bytes in
    /// percent form. That covers everything git refuses (spaces, dots at the
    /// ends, `..`, `@{`, `~^:?*[\` and controls) and stays reversible.
    static func refComponent(_ name: String) -> String {
        var out = ""
        for scalar in name.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "-" || scalar == "_" {
                out.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    out += String(format: "%%%02X", byte)
                }
            }
        }
        return out.isEmpty ? "Take" : out
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
