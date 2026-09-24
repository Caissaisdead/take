import Foundation

/// The three emphasis forms prose Markdown uses, matched the same way in the
/// editor (which keeps the markers, dimmed) and in exports (which drop them).
public enum MarkdownEmphasis {
    public static let bold = try! NSRegularExpression(pattern: #"\*\*(?=\S)([^*\n]+?)(?<=\S)\*\*"#)
    public static let italic = try! NSRegularExpression(pattern: #"(?<!\*)\*(?=[^\s*])([^*\n]+?)(?<=\S)\*(?!\*)"#)
    // The sample scene marks italics with underscores, as much prose Markdown does.
    public static let underscoreItalic = try! NSRegularExpression(pattern: #"(?<![\w_])_(?=[^\s_])([^_\n]+?)(?<=\S)_(?![\w_])"#)

    /// `* * *` or `---` on a line of its own.
    public static func isSceneBreak(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
        return trimmed == "* * *" || trimmed == "---"
    }

    public enum Trait { case bold, italic }

    /// A paragraph with its markers removed and the ranges (in the result) that
    /// carried them. Bold is read first, so `**a *b* c**` is bold with an italic
    /// run inside.
    public static func strip(_ paragraph: String) -> (text: String, runs: [(range: NSRange, trait: Trait)]) {
        var text = paragraph as NSString
        var runs: [(NSRange, Trait)] = []
        for (pattern, trait) in [(bold, Trait.bold), (italic, .italic), (underscoreItalic, .italic)] {
            let matches = pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length))
            // Back to front, so earlier ranges stay valid while markers vanish.
            for match in matches.reversed() {
                let outer = match.range
                let inner = match.range(at: 1)
                let closingLength = outer.location + outer.length - inner.location - inner.length
                let openingLength = inner.location - outer.location
                text = text.replacingCharacters(in: NSRange(location: inner.location + inner.length, length: closingLength), with: "") as NSString
                text = text.replacingCharacters(in: NSRange(location: outer.location, length: openingLength), with: "") as NSString
                // Runs already found move with the text: after the match they
                // shift left by both markers, and a run that contains the match
                // shrinks by both.
                let outerEnd = outer.location + outer.length
                runs = runs.map { run in
                    var range = run.0
                    let end = range.location + range.length
                    if range.location >= outerEnd {
                        range.location -= openingLength + closingLength
                    } else if range.location <= outer.location, end >= outerEnd {
                        range.length -= openingLength + closingLength
                    } else if range.location >= outer.location, end <= outerEnd {
                        range.location -= openingLength
                    }
                    return (range, run.1)
                }
                runs.append((NSRange(location: outer.location, length: inner.length), trait))
            }
        }
        return (text as String, runs.map { (range: $0.0, trait: $0.1) })
    }
}
