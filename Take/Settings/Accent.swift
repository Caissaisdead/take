import AppKit
import SwiftUI

/// The colour the app's controls, selections, Compare's links and live takes
/// are drawn in. Six to choose from in Settings; the choice is the writer's,
/// kept on this Mac, and never part of a project.
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

    var color: Color {
        let (light, dark) = pair
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
