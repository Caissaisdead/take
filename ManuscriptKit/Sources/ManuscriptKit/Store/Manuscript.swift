import Foundation

/// A scene's identity, stable across renames, moves and takes.
public struct SceneID: Hashable, Codable, Sendable {
    public let uuid: UUID

    public init() { uuid = UUID() }
    public init(uuid: UUID) { self.uuid = uuid }
}

/// Where a scene lives in the repository and what it is called.
public struct SceneRef: Codable, Hashable, Sendable, Identifiable {
    public var id: SceneID
    public var title: String
    /// Path relative to the repository root, e.g. `chapters/01-longbourn/01-a-truth.md`.
    /// Fixed when the scene is added; a rename or a move never changes it.
    public var path: String
    /// What the scene is for, in the writer's own line. Shown under the title
    /// and handed to the engines.
    public var synopsis: String
    /// The writer's notes on the scene, never part of the draft.
    public var notes: String

    public init(id: SceneID, title: String, path: String, synopsis: String = "", notes: String = "") {
        self.id = id
        self.title = title
        self.path = path
        self.synopsis = synopsis
        self.notes = notes
    }

    /// A manifest of format 2 has no synopsis or notes; they read as empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SceneID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        path = try container.decode(String.self, forKey: .path)
        synopsis = try container.decodeIfPresent(String.self, forKey: .synopsis) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

public struct Chapter: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// The folder its scenes are written under, e.g. `chapters/01-longbourn`.
    /// Fixed when the chapter is added, whatever it is later called or wherever
    /// it is moved.
    public var folder: String
    public var scenes: [SceneRef]

    public init(id: UUID = UUID(), title: String, folder: String, scenes: [SceneRef] = []) {
        self.id = id
        self.title = title
        self.folder = folder
        self.scenes = scenes
    }
}

/// A part gathers chapters. A manuscript that has no use for parts keeps its
/// chapters in one part with an empty title, which the app shows as no part at
/// all.
public struct Part: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var chapters: [Chapter]

    public init(id: UUID = UUID(), title: String, chapters: [Chapter] = []) {
        self.id = id
        self.title = title
        self.chapters = chapters
    }
}

/// The manifest: the order of everything, kept in `manuscript.json` at the root.
/// Order lives here and never in file names, so reordering never conflicts with
/// editing. The structure is parts, then chapters, then scenes; only scenes have
/// files.
public struct Manuscript: Codable, Hashable, Sendable {
    public static let manifestPath = "manuscript.json"
    /// The shape this version of the code writes and reads. Bumped whenever the
    /// JSON changes in a way an older reader would misread. Format 2 lacked the
    /// scene synopsis and notes and the targets; it is read with those empty
    /// and written back as 3.
    public static let currentFormat = 3
    public static let readableFormats = 2...3

    public var format: Int
    public var title: String
    public var parts: [Part]
    /// Words the whole draft is aiming for, when the writer has said.
    public var target: Int?
    /// Words a day, when the writer has said.
    public var dailyTarget: Int?

    public init(title: String, parts: [Part] = []) {
        format = Self.currentFormat
        self.title = title
        self.parts = parts
    }

    // MARK: - Reading

    public var chapters: [Chapter] { parts.flatMap(\.chapters) }
    public var scenes: [SceneRef] { chapters.flatMap(\.scenes) }

    /// Whether parts are shown at all: when there is more than one, or any
    /// has a title. One untitled part is no part.
    public var usesParts: Bool {
        parts.count > 1 || parts.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public func part(_ id: UUID) -> Part? {
        parts.first { $0.id == id }
    }

    public func chapter(_ id: UUID) -> Chapter? {
        chapters.first { $0.id == id }
    }

    public func scene(_ id: SceneID) -> SceneRef? {
        scenes.first { $0.id == id }
    }

    /// The manuscript cut down to one chapter, for exporting it alone: the
    /// same title, one untitled part, that chapter. Nil for a chapter that is
    /// not here.
    public func only(chapter id: UUID) -> Manuscript? {
        guard let chapter = chapter(id) else { return nil }
        var cut = Manuscript(title: title, parts: [Part(title: "", chapters: [chapter])])
        cut.target = target
        cut.dailyTarget = dailyTarget
        return cut
    }

    public func part(containing chapter: UUID) -> Part? {
        parts.first { $0.chapters.contains { $0.id == chapter } }
    }

    public func chapter(containing scene: SceneID) -> Chapter? {
        chapters.first { $0.scenes.contains { $0.id == scene } }
    }

    // MARK: - Shaping

    /// Every mutation below leaves the manuscript as it was when it throws.

    public mutating func append(_ part: Part) {
        parts.append(part)
    }

    public mutating func append(_ chapter: Chapter, toPart part: UUID) throws {
        let p = try partIndex(part)
        parts[p].chapters.append(chapter)
    }

    /// At `index` among the chapter's scenes, or at the end.
    public mutating func insert(_ scene: SceneRef, inChapter chapter: UUID, at index: Int? = nil) throws {
        let (p, c) = try chapterIndex(chapter)
        let count = parts[p].chapters[c].scenes.count
        parts[p].chapters[c].scenes.insert(scene, at: min(index ?? count, count))
    }

    public mutating func rename(part id: UUID, to title: String) throws {
        parts[try partIndex(id)].title = title
    }

    public mutating func rename(chapter id: UUID, to title: String) throws {
        let (p, c) = try chapterIndex(id)
        parts[p].chapters[c].title = title
    }

    public mutating func rename(scene id: SceneID, to title: String) throws {
        let (p, c, s) = try sceneIndex(id)
        parts[p].chapters[c].scenes[s].title = title
    }

    public mutating func set(synopsis: String, notes: String, forScene id: SceneID) throws {
        let (p, c, s) = try sceneIndex(id)
        parts[p].chapters[c].scenes[s].synopsis = synopsis
        parts[p].chapters[c].scenes[s].notes = notes
    }

    /// Takes the scene out of wherever it is and puts it at `index` among the
    /// scenes of `chapter`, counted after the removal. An index past the end
    /// means last.
    public mutating func move(scene id: SceneID, toChapter chapter: UUID, at index: Int) throws {
        _ = try chapterIndex(chapter)
        let (p, c, s) = try sceneIndex(id)
        let scene = parts[p].chapters[c].scenes.remove(at: s)
        let (tp, tc) = try chapterIndex(chapter)
        parts[tp].chapters[tc].scenes.insert(scene, at: min(index, parts[tp].chapters[tc].scenes.count))
    }

    public mutating func move(chapter id: UUID, toPart part: UUID, at index: Int) throws {
        _ = try partIndex(part)
        let (p, c) = try chapterIndex(id)
        let chapter = parts[p].chapters.remove(at: c)
        let tp = try partIndex(part)
        parts[tp].chapters.insert(chapter, at: min(index, parts[tp].chapters.count))
    }

    public mutating func move(part id: UUID, to index: Int) throws {
        let part = parts.remove(at: try partIndex(id))
        parts.insert(part, at: min(index, parts.count))
    }

    @discardableResult
    public mutating func remove(scene id: SceneID) throws -> SceneRef {
        let (p, c, s) = try sceneIndex(id)
        return parts[p].chapters[c].scenes.remove(at: s)
    }

    /// The chapter and every scene in it.
    @discardableResult
    public mutating func remove(chapter id: UUID) throws -> Chapter {
        let (p, c) = try chapterIndex(id)
        return parts[p].chapters.remove(at: c)
    }

    /// The part and everything under it.
    @discardableResult
    public mutating func remove(part id: UUID) throws -> Part {
        parts.remove(at: try partIndex(id))
    }

    // MARK: - Finding

    private func partIndex(_ id: UUID) throws -> Int {
        guard let p = parts.firstIndex(where: { $0.id == id }) else { throw ProjectStoreError.unknownPart(id) }
        return p
    }

    private func chapterIndex(_ id: UUID) throws -> (Int, Int) {
        for (p, part) in parts.enumerated() {
            if let c = part.chapters.firstIndex(where: { $0.id == id }) { return (p, c) }
        }
        throw ProjectStoreError.unknownChapter(id)
    }

    private func sceneIndex(_ id: SceneID) throws -> (Int, Int, Int) {
        for (p, part) in parts.enumerated() {
            for (c, chapter) in part.chapters.enumerated() {
                if let s = chapter.scenes.firstIndex(where: { $0.id == id }) { return (p, c, s) }
            }
        }
        throw ProjectStoreError.unknownScene(id)
    }
}

/// A chapter or scene number as folders and files carry it: two digits
/// while there are fewer than a hundred.
func number(_ n: Int) -> String {
    n < 10 ? "0\(n)" : "\(n)"
}

/// One saved state of a scene, as shown in its history.
public struct Version: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable { case checkpoint, keep }

    public var id: ObjectID
    public var date: Date
    public var message: String
    public var kind: Kind

    public init(id: ObjectID, date: Date, message: String, kind: Kind) {
        self.id = id
        self.date = date
        self.message = message
        self.kind = kind
    }
}

/// A scene taken out of the manuscript, as history remembers it.
public struct RemovedScene: Hashable, Sendable, Identifiable {
    public var scene: SceneRef
    /// The chapter it was in, and what that chapter was called then.
    public var chapter: UUID
    public var chapterTitle: String
    /// The commit that removed it, and the one before, which still has its text.
    public var removedAt: ObjectID
    public var before: ObjectID
    public var date: Date

    public var id: SceneID { scene.id }

    public init(scene: SceneRef, chapter: UUID, chapterTitle: String, removedAt: ObjectID, before: ObjectID, date: Date) {
        self.scene = scene
        self.chapter = chapter
        self.chapterTitle = chapterTitle
        self.removedAt = removedAt
        self.before = before
        self.date = date
    }
}

/// How one scene stands against an earlier state of the draft.
public struct SceneChange: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable { case added, removed, changed, same }

    public var scene: SceneRef
    /// The chapter it is in now, or was in for a removed scene.
    public var chapter: UUID
    public var kind: Kind
    public var wordsAdded: Int
    public var wordsRemoved: Int

    public var id: SceneID { scene.id }

    public init(scene: SceneRef, chapter: UUID, kind: Kind, wordsAdded: Int, wordsRemoved: Int) {
        self.scene = scene
        self.chapter = chapter
        self.kind = kind
        self.wordsAdded = wordsAdded
        self.wordsRemoved = wordsRemoved
    }
}

/// A named state of the whole draft: an annotated tag on a main commit under
/// `refs/tags/milestones/<slug>`. Nothing in the draft changes when one is
/// marked; the scene that did not move still has this as a version to compare
/// against.
public struct Milestone: Hashable, Sendable, Identifiable {
    /// The full ref name.
    public var id: String
    public var name: String
    /// The main commit the milestone marks.
    public var commit: ObjectID
    public var date: Date

    public init(id: String, name: String, commit: ObjectID, date: Date) {
        self.id = id
        self.name = name
        self.commit = commit
        self.date = date
    }
}

/// A take: a branch scoped to one scene, made from main, kept or discarded.
public struct Take: Hashable, Sendable, Identifiable {
    /// The full ref name, `refs/takes/<scene uuid>/<slug>`.
    public var id: String
    public var scene: SceneID
    /// The slug that ends the ref, `take-2` for a take begun as "Take 2": the
    /// take's identity, the same whether it was just created or listed. Rendering
    /// it as a title is the app's job.
    public var name: String
    /// The main commit the take was made from.
    public var base: ObjectID
    public var head: ObjectID

    public init(id: String, scene: SceneID, name: String, base: ObjectID, head: ObjectID) {
        self.id = id
        self.scene = scene
        self.name = name
        self.base = base
        self.head = head
    }
}

/// Which whole scene wins when a keep meets a main that moved.
public enum KeepSide: Sendable, Equatable {
    case take
    case main
}

public enum KeepResult: Sendable, Equatable {
    /// Main now carries the take's scene. The merge commit is returned, or main's
    /// unchanged head when the take had no commits of its own.
    case kept(ObjectID)
    /// Main's scene changed since the take began. Nothing was written.
    case conflict(base: String, main: String, take: String)
}
