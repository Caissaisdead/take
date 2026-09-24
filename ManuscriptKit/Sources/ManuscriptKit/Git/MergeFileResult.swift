import Foundation

/// The outcome of a three-way merge of one file's contents.
public struct MergeFileResult: Sendable {
    /// True when every hunk came from one side only, so `content` has no markers.
    public let isAutomergeable: Bool
    /// The merged bytes; with conflict markers when not automergeable.
    public let content: Data

    public init(isAutomergeable: Bool, content: Data) {
        self.isAutomergeable = isAutomergeable
        self.content = content
    }
}
