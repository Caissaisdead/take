import Foundation

/// An annotated tag as read back from the repository.
public struct TagInfo: Hashable, Sendable, Identifiable {
    public let id: ObjectID
    /// The short name, as it appears after `refs/tags/`.
    public let name: String
    /// The commit the tag points at.
    public let target: ObjectID
    public let tagger: Signature
    public let message: String

    public init(id: ObjectID, name: String, target: ObjectID, tagger: Signature, message: String) {
        self.id = id
        self.name = name
        self.target = target
        self.tagger = tagger
        self.message = message
    }
}
