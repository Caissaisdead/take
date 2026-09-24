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

    public init(id: SceneID, title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
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
    /// JSON changes in a way an older reader would misread.
    public static let currentFormat = 2

    public var format: Int
    public var title: String
    public var parts: [Part]

    public init(title: String, parts: [Part] = []) {
        format = Self.currentFormat
        self.title = title
        self.parts = parts
    }

    // MARK: - Reading

    public var chapters: [Chapter] { parts.flatMap(\.chapters) }
    public var scenes: [SceneRef] { chapters.flatMap(\.scenes) }

    public func part(_ id: UUID) -> Part? {
        parts.first { $0.id == id }
    }

    public func chapter(_ id: UUID) -> Chapter? {
        chapters.first { $0.id == id }
    }

    public func scene(_ id: SceneID) -> SceneRef? {
        scenes.first { $0.id == id }
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

/// One saved state of a scene, as shown in its history.
public struct Version: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable { case checkpoint, milestone, keep }

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

public enum KeepResult: Sendable, Equatable {
    /// Main now carries the take's scene. The merge commit is returned, or main's
    /// unchanged head when the take had no commits of its own.
    case kept(ObjectID)
    /// Main's scene changed since the take began. Nothing was written.
    case conflict(base: String, main: String, take: String)
}
