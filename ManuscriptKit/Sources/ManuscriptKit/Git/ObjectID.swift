import Foundation

/// A git object id: forty lowercase hex characters.
public struct ObjectID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let hex: String

    public init?(hex: String) {
        let lowered = hex.lowercased()
        guard lowered.count == 40, lowered.allSatisfy({ $0.isHexDigit }) else { return nil }
        self.hex = lowered
    }

    /// The first seven characters, the way git shows one.
    public var short: String { String(hex.prefix(7)) }
    public var description: String { hex }
}
