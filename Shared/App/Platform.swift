import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The few words and facts that differ by device.
enum Platform {
    #if os(iOS)
    /// How the device names itself in a sentence: "this iPhone".
    static let deviceName = "iPhone"
    /// The commits' author: the name the phone was given.
    static var authorName: String { UIDevice.current.name }
    #else
    static let deviceName = "Mac"
    static var authorName: String { NSFullUserName() }
    #endif
}
