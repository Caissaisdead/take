import Foundation

/// One entry of a tree: a file (blob) or a folder (tree).
public struct TreeEntry: Hashable, Sendable {
    public enum Kind: Sendable { case blob, tree }

    public let name: String
    public let id: ObjectID
    public let kind: Kind

    public init(name: String, id: ObjectID, kind: Kind) {
        self.name = name
        self.id = id
        self.kind = kind
    }
}
