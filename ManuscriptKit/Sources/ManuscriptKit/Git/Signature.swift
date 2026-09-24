import Foundation

/// Who made a commit, and when.
public struct Signature: Hashable, Sendable {
    public var name: String
    public var email: String
    public var time: Date

    public init(name: String, email: String, time: Date = Date()) {
        self.name = name
        self.email = email
        self.time = time
    }
}
