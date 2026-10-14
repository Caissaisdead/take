import ManuscriptKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Turns a `ProseDiff` into styled text for the compare pane. Paragraphs sit a
/// blank line apart; whole-paragraph changes colour the paragraph, in-place
/// edits colour their words. Decoration stops before a token's trailing space
/// so a struck word does not drag its line across the gap.
@MainActor
enum DiffRenderer {
    /// Links at the end of a changed paragraph name the segment they act on.
    nonisolated static let pickScheme = "take-pick"

    nonisolated static func segment(in link: URL) -> Int? {
        guard link.scheme == pickScheme else { return nil }
        return Int(link.lastPathComponent)
    }

    static func render(_ diff: ProseDiff, accent: Accent = .blue) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, segment) in diff.segments.enumerated() {
            if index > 0 { out.append(run("\n\n", color: ProseStyle.labelColor)) }
            switch segment {
            case .equal(let paragraph):
                out.append(run(paragraph, color: ProseStyle.secondaryColor))
            case .removed(let paragraph):
                out.append(run(paragraph, color: .systemRed, decoration: .strikethroughStyle))
                out.append(pick("bring back", segment: index, accent: accent))
            case .inserted(let paragraph):
                out.append(run(paragraph, color: .systemGreen, decoration: .underlineStyle))
                out.append(pick("drop", segment: index, accent: accent))
            case .changed(_, _, let words):
                for word in words {
                    switch word {
                    case .equal(let token):
                        out.append(run(token, color: ProseStyle.labelColor))
                    case .removed(let token):
                        out.append(run(token, color: .systemRed, decoration: .strikethroughStyle))
                    case .inserted(let token):
                        out.append(run(token, color: .systemGreen, decoration: .underlineStyle))
                    }
                }
                out.append(pick("take theirs", segment: index, accent: accent))
            }
        }
        return out
    }

    /// A small link after a paragraph: what taking the other side would do.
    private static func pick(_ verb: String, segment: Int, accent: Accent) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.systemFont(ofSize: PlatformFont.smallSystemFontSize),
            .foregroundColor: accent.platformColor,
            .link: URL(string: "\(pickScheme)://segment/\(segment)")!,
            .paragraphStyle: paragraphStyle,
        ]
        return NSAttributedString(string: "  ⟵ \(verb)", attributes: attributes)
    }

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = ProseStyle.lineHeight
        return style
    }()

    private static func run(_ token: String, color: PlatformColor, decoration: NSAttributedString.Key? = nil) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ProseStyle.font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        let result = NSMutableAttributedString(string: token, attributes: attributes)
        guard let decoration else { return result }
        let text = token as NSString
        let trailing = text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: .backwards)
        let wordLength = trailing.location == NSNotFound ? 0 : trailing.location + trailing.length
        if wordLength > 0 {
            result.addAttribute(decoration, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: wordLength))
        }
        return result
    }
}
