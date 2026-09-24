import Foundation

/// The rules for prose as it is stored: Markdown, one paragraph per line, a blank
/// line between paragraphs, no hard wrapping. Every diff, prompt and export reads
/// this form, so the rules live in one place.
///
/// The editor shows the same prose with no blank lines at all, one paragraph
/// per line, so that a return is always a new paragraph; `editorForm` and
/// `paragraphsByLine` convert at that boundary.
public enum Prose {
    /// The paragraphs of a text: split on blank lines, line endings normalised,
    /// trailing whitespace trimmed, empty paragraphs dropped. A paragraph never
    /// contains a newline.
    public static func paragraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var lines: [Substring] = []

        func flush() {
            guard !lines.isEmpty else { return }
            paragraphs.append(lines.joined(separator: " "))
            lines.removeAll(keepingCapacity: true)
        }

        // "\r\n" is a single Character, so no pre-pass is needed to normalise it.
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: isLineBreak) {
            // Trailing spaces on a wrapped line belong to the wrap, not the writer;
            // trimming per line is what lets the join below use exactly one space.
            let content = trimmingTrailingWhitespace(line)
            if content.isEmpty { flush() } else { lines.append(content) }
        }
        flush()
        return paragraphs
    }

    /// Paragraphs back into stored form: joined by a blank line, ending in one newline.
    public static func join(_ paragraphs: [String]) -> String {
        paragraphs.isEmpty ? "" : paragraphs.joined(separator: "\n\n") + "\n"
    }

    /// `join(paragraphs(text))`.
    public static func normalize(_ text: String) -> String {
        join(paragraphs(text))
    }

    /// Stored prose as the editor shows it: the paragraphs on consecutive
    /// lines, no blank lines, no trailing newline.
    public static func editorForm(_ text: String) -> String {
        paragraphs(text).joined(separator: "\n")
    }

    /// The paragraphs of editor text, where every line break ends a paragraph:
    /// trailing whitespace trimmed, blank lines dropped. `join` of these is the
    /// stored form.
    public static func paragraphsByLine(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: isLineBreak)
            .map(trimmingTrailingWhitespace)
            .filter { !$0.isEmpty }
            .map(String.init)
    }

    /// The number of whitespace-separated runs in the whole text, as a writer
    /// would count words. Line breaks and paragraph breaks count as whitespace.
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for character in text {
            if character.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// A paragraph as tokens for word diffing: each word carries the whitespace
    /// that follows it, so `tokens(p).joined() == p`. Leading whitespace, when a
    /// paragraph has any, is a token of its own.
    public static func tokens(_ paragraph: String) -> [String] {
        var tokens: [String] = []
        let end = paragraph.endIndex
        var start = paragraph.startIndex
        var cursor = start

        func advance(while predicate: (Character) -> Bool) {
            while cursor < end, predicate(paragraph[cursor]) {
                cursor = paragraph.index(after: cursor)
            }
        }

        advance(while: \.isWhitespace)
        if cursor > start {
            tokens.append(String(paragraph[start..<cursor]))
            start = cursor
        }
        while cursor < end {
            advance(while: { !$0.isWhitespace })
            advance(while: \.isWhitespace)
            tokens.append(String(paragraph[start..<cursor]))
            start = cursor
        }
        return tokens
    }

    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n" || character == "\r"
    }

    private static func trimmingTrailingWhitespace(_ line: Substring) -> Substring {
        guard let last = line.lastIndex(where: { !$0.isWhitespace }) else { return line[line.startIndex..<line.startIndex] }
        return line[...last]
    }
}
