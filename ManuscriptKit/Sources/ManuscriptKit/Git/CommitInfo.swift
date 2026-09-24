import Foundation

/// A commit as read back from the repository.
public struct CommitInfo: Hashable, Sendable, Identifiable {
    public let id: ObjectID
    public let parents: [ObjectID]
    public let tree: ObjectID
    public let author: Signature
    public let message: String

    public init(id: ObjectID, parents: [ObjectID], tree: ObjectID, author: Signature, message: String) {
        self.id = id
        self.parents = parents
        self.tree = tree
        self.author = author
        self.message = message
    }
}
