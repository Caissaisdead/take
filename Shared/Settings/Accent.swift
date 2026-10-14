import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// The colour the app's controls, selections, Compare's links and live takes
/// are drawn in. Six to choose from in Settings; the choice is the writer's,
/// kept on this device, and never part of a project.
enum Accent: String, CaseIterable, Identifiable {
    case blue, indigo, plum, rust, moss, graphite

    static let key = "Accent"

    var id: String { rawValue }

    /// The choice as saved, blue until the writer says otherwise.
    static var current: Accent {
        UserDefaults.standard.string(forKey: key).flatMap(Accent.init(rawValue:)) ?? .blue
    }

    var name: String {
        switch self {
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .plum: return "Plum"
        case .rust: return "Rust"
        case .moss: return "Moss"
        case .graphite: return "Graphite"
        }
    }

    /// One value for the light appearance and one for the dark, each picked
    /// to read on its ground at the same weight, so a selection or a tinted
    /// take looks the same choice in either.
    private var pair: (light: UInt32, dark: UInt32) {
        switch self {
        case .blue: return (0x2F5FD0, 0x6E93F0)
        case .indigo: return (0x5B57CC, 0x8E8BEB)
        case .plum: return (0x99428F, 0xCC7BC2)
        case .rust: return (0xC25733, 0xE78A67)
        case .moss: return (0x3D8757, 0x7CC492)
        case .graphite: return (0x6B707A, 0xA6ABB5)
        }
    }

    var color: Color { Color(light: pair.light, dark: pair.dark) }

    /// The same colour for the text views: the caret, the selection,
    /// Compare's links.
    var platformColor: PlatformColor { .dynamic(light: pair.light, dark: pair.dark) }
}

extension PlatformColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        #if canImport(UIKit)
        self.init(red: red, green: green, blue: blue, alpha: 1)
        #else
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
        #endif
    }

    /// A colour that follows the appearance: `light` in the light one, `dark`
    /// in the dark.
    static func dynamic(light: UInt32, dark: UInt32) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
        #else
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
        #endif
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: .dynamic(light: light, dark: dark))
        #else
        self.init(nsColor: .dynamic(light: light, dark: dark))
        #endif
    }

    /// The platform's ground for a card or a control: the map's beads and cards.
    static var cardBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
