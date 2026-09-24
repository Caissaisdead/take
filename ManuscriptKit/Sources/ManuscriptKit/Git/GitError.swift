import Foundation

/// A libgit2 failure, carried with the call that failed and libgit2's own message.
public struct GitError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let code: Int32
    public let message: String

    public init(operation: String, code: Int32, message: String) {
        self.operation = operation
        self.code = code
        self.message = message
    }

    public var description: String { "\(operation): \(message) (\(code))" }
}
