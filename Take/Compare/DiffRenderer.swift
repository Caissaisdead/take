import AppKit
import ManuscriptKit

/// Turns a `ProseDiff` into styled text for the compare pane. Paragraphs sit a
/// blank line apart; whole-paragraph changes colour the paragraph, in-place
/// edits colour their words. Decoration stops before a token's trailing space
/// so a struck word does not drag its line across the gap.
@MainActor
enum DiffRenderer {
    static func render(_ diff: ProseDiff) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, segment) in diff.segments.enumerated() {
            if index > 0 { out.append(run("\n\n", color: .labelColor)) }
            switch segment {
            case .equal(let paragraph):
                out.append(run(paragraph, color: .secondaryLabelColor))
            case .removed(let paragraph):
                out.append(run(paragraph, color: .systemRed, decoration: .strikethroughStyle))
            case .inserted(let paragraph):
                out.append(run(paragraph, color: .systemGreen, decoration: .underlineStyle))
            case .changed(_, _, let words):
                for word in words {
                    switch word {
                    case .equal(let token):
                        out.append(run(token, color: .labelColor))
                    case .removed(let token):
                        out.append(run(token, color: .systemRed, decoration: .strikethroughStyle))
                    case .inserted(let token):
                        out.append(run(token, color: .systemGreen, decoration: .underlineStyle))
                    }
                }
            }
        }
        return out
    }

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.5
        return style
    }()

    private static func run(_ token: String, color: NSColor, decoration: NSAttributedString.Key? = nil) -> NSAttributedString {
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
