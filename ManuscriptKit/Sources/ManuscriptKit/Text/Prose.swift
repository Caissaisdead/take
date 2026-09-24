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

    /// A writer's note in the prose, `[[like this]]`: shown dimmed, listed in
    /// the Scene pane, and never part of the draft that leaves the app.
    public struct Note: Hashable, Sendable, Identifiable {
        public var paragraph: Int
        /// The whole `[[…]]` within the paragraph, in UTF-16 units.
        public var location: Int
        public var length: Int
        /// What is between the brackets, trimmed.
        public var text: String

        public var id: String { "\(paragraph):\(location)" }
    }

    public static let notePattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]*)\]\]"#)

    /// Every note in the text, in order.
    public static func notes(in text: String) -> [Note] {
        var notes: [Note] = []
        for (index, paragraph) in paragraphs(text).enumerated() {
            let whole = NSRange(location: 0, length: (paragraph as NSString).length)
            for match in notePattern.matches(in: paragraph, range: whole) {
                let inner = (paragraph as NSString).substring(with: match.range(at: 1))
                notes.append(Note(paragraph: index, location: match.range.location, length: match.range.length, text: inner.trimmingCharacters(in: .whitespaces)))
            }
        }
        return notes
    }

    /// The text with every note taken out, in stored form: the space a note
    /// left is closed up, and a paragraph that was only a note goes.
    public static func withoutNotes(_ text: String) -> String {
        var kept: [String] = []
        for paragraph in paragraphs(text) {
            let whole = NSRange(location: 0, length: (paragraph as NSString).length)
            guard notePattern.firstMatch(in: paragraph, range: whole) != nil else {
                kept.append(paragraph)
                continue
            }
            var cleaned = notePattern.stringByReplacingMatches(in: paragraph, range: whole, withTemplate: "")
            cleaned = cleaned.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: #" ([,.;:!?])"#, with: "$1", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty { kept.append(cleaned) }
        }
        return join(kept)
    }

    /// Where the `paragraph`th paragraph's `location..<location+length` (UTF-16
    /// units within the paragraph) falls in editor text: the offset of that
    /// paragraph's line plus the location. Blank lines in the editor are not
    /// paragraphs and are skipped over; nil when the editor has fewer
    /// paragraphs than that.
    public static func editorRange(paragraph: Int, location: Int, length: Int, in editorText: String) -> (location: Int, length: Int)? {
        var offset = 0
        var seen = 0
        for line in editorText.split(omittingEmptySubsequences: false, whereSeparator: isLineBreak) {
            let blank = trimmingTrailingWhitespace(line).isEmpty
            if !blank {
                if seen == paragraph { return (offset + location, length) }
                seen += 1
            }
            offset += line.utf16.count + 1
        }
        return nil
    }

    /// The first `words` words, in whole paragraphs, in stored form. Always at
    /// least the first paragraph, however long.
    public static func head(_ text: String, words: Int) -> String {
        var kept: [String] = []
        var count = 0
        for paragraph in paragraphs(text) {
            let n = wordCount(paragraph)
            if count + n > words, !kept.isEmpty { break }
            kept.append(paragraph)
            count += n
        }
        return join(kept)
    }

    /// The last `words` words, in whole paragraphs, in stored form. Always at
    /// least the last paragraph.
    public static func tail(_ text: String, words: Int) -> String {
        var kept: [String] = []
        var count = 0
        for paragraph in paragraphs(text).reversed() {
            let n = wordCount(paragraph)
            if count + n > words, !kept.isEmpty { break }
            kept.insert(paragraph, at: 0)
            count += n
        }
        return join(kept)
    }

    /// Roughly 3.5 characters per token in English prose, erring toward more
    /// tokens so a trim happens before a model's refusal does.
    public static func estimateTokens(_ text: String) -> Int {
        (text.utf8.count * 2 + 6) / 7
    }

    /// Whole paragraphs from the top until `budget` tokens are spent, or every
    /// paragraph when the whole text fits. When not even the first fits, as
    /// much of it as does. `total` is how many paragraphs there were and
    /// `whole` whether all of them are in `kept`, unshortened.
    public static func prefix(_ text: String, withinTokens budget: Int) -> (kept: [String], total: Int, whole: Bool) {
        let all = paragraphs(text)
        guard estimateTokens(text) > budget else { return (all, all.count, true) }
        var kept: [String] = []
        var used = 0
        for paragraph in all {
            let cost = estimateTokens(paragraph) + 1
            if used + cost > budget { break }
            kept.append(paragraph)
            used += cost
        }
        if kept.isEmpty, let first = all.first {
            return ([String(first.prefix(budget * 3))], all.count, false)
        }
        return (kept, all.count, kept.count == all.count)
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
