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
    public var scenes: [SceneRef]

    public init(id: UUID = UUID(), title: String, scenes: [SceneRef] = []) {
        self.id = id
        self.title = title
        self.scenes = scenes
    }
}

/// The manifest: the order of everything, kept in `manuscript.json` at the root.
/// Order lives here and never in file names, so reordering never conflicts with
/// editing.
public struct Manuscript: Codable, Hashable, Sendable {
    public static let manifestPath = "manuscript.json"

    public var title: String
    public var chapters: [Chapter]

    public init(title: String, chapters: [Chapter] = []) {
        self.title = title
        self.chapters = chapters
    }

    public func scene(_ id: SceneID) -> SceneRef? {
        for chapter in chapters {
            if let scene = chapter.scenes.first(where: { $0.id == id }) { return scene }
        }
        return nil
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
