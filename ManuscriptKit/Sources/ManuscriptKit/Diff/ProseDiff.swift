import Foundation

/// One token's fate in a word-level diff. Tokens carry their trailing whitespace.
public enum WordChange: Sendable, Equatable {
    case equal(String)
    case inserted(String)
    case removed(String)
}

/// A paragraph-level diff of two texts, with word-level detail inside paragraphs
/// that changed. The unit is the paragraph, never the line: that is what makes a
/// diff of prose readable.
public struct ProseDiff: Sendable, Equatable {
    public enum Segment: Sendable, Equatable {
        case equal(String)
        case inserted(String)
        case removed(String)
        /// A paragraph edited in place: the old and new text, and the words between.
        case changed(old: String, new: String, words: [WordChange])
    }

    public struct Summary: Sendable, Equatable {
        public var paragraphsChanged: Int
        public var wordsAdded: Int
        public var wordsRemoved: Int

        public init(paragraphsChanged: Int, wordsAdded: Int, wordsRemoved: Int) {
            self.paragraphsChanged = paragraphsChanged
            self.wordsAdded = wordsAdded
            self.wordsRemoved = wordsRemoved
        }
    }

    public let segments: [Segment]

    public init(segments: [Segment]) {
        self.segments = segments
    }

    public var hasChanges: Bool {
        segments.contains { if case .equal = $0 { return false } else { return true } }
    }

    /// Paragraphs inserted, removed or changed, and the words added and removed
    /// across all of them. A changed paragraph contributes only the words that
    /// differ; a whole paragraph contributes every one of its words. Counted as
    /// `Prose.wordCount` does, so a leading-whitespace token is not a word.
    public var summary: Summary {
        var summary = Summary(paragraphsChanged: 0, wordsAdded: 0, wordsRemoved: 0)
        for segment in segments {
            switch segment {
            case .equal:
                break
            case .inserted(let text):
                summary.paragraphsChanged += 1
                summary.wordsAdded += Prose.wordCount(text)
            case .removed(let text):
                summary.paragraphsChanged += 1
                summary.wordsRemoved += Prose.wordCount(text)
            case .changed(_, _, let words):
                summary.paragraphsChanged += 1
                for word in words {
                    switch word {
                    case .equal: break
                    case .inserted(let text): summary.wordsAdded += Prose.wordCount(text)
                    case .removed(let text): summary.wordsRemoved += Prose.wordCount(text)
                    }
                }
            }
        }
        return summary
    }
}

public enum ProseDiffer {
    /// Paragraph diff first (Myers over paragraph hashes), then word diff inside
    /// each removed/inserted pair that is similar enough to be the same paragraph
    /// edited. Never runs a word diff across the whole text.
    public static func diff(old: String, new: String) -> ProseDiff {
        let oldParagraphs = Prose.paragraphs(old).map(Paragraph.init)
        let newParagraphs = Prose.paragraphs(new).map(Paragraph.init)
        let difference = newParagraphs.difference(from: oldParagraphs)

        var segments: [ProseDiff.Segment] = []
        var removed: [String] = []
        var inserted: [String] = []

        // A hunk is a run of removals followed by insertions. Pairing by position
        // is deliberately naive: a writer edits paragraphs in place far more often
        // than they reorder them, and a bad pair falls back to removed + inserted.
        func flushHunk() {
            let paired = min(removed.count, inserted.count)
            for k in 0..<paired {
                let words = tokenDiff(old: Prose.tokens(removed[k]), new: Prose.tokens(inserted[k]))
                if words.isSameParagraphEdited {
                    segments.append(.changed(old: removed[k], new: inserted[k], words: words.changes))
                } else {
                    segments.append(.removed(removed[k]))
                    segments.append(.inserted(inserted[k]))
                }
            }
            for text in removed[paired...] { segments.append(.removed(text)) }
            for text in inserted[paired...] { segments.append(.inserted(text)) }
            removed.removeAll(keepingCapacity: true)
            inserted.removeAll(keepingCapacity: true)
        }

        walk(difference, old: oldParagraphs, new: newParagraphs) { change in
            switch change {
            case .removed(let index):
                removed.append(oldParagraphs[index].text)
            case .inserted(let index):
                inserted.append(newParagraphs[index].text)
            case .equal(let index):
                flushHunk()
                segments.append(.equal(oldParagraphs[index].text))
            }
        }
        flushHunk()
        return ProseDiff(segments: segments)
    }

    /// Word-level diff of two paragraphs using `Prose.tokens`. Adjacent tokens with
    /// the same fate are merged into one change, so a renderer gets few segments.
    public static func wordDiff(old: String, new: String) -> [WordChange] {
        tokenDiff(old: Prose.tokens(old), new: Prose.tokens(new)).changes
    }

    /// A paragraph compared by hash before text, so Myers over hundreds of
    /// paragraphs never walks two long, nearly identical strings to find they differ.
    private struct Paragraph: Equatable {
        let text: String
        let hash: Int

        init(_ text: String) {
            self.text = text
            var hasher = Hasher()
            hasher.combine(text)
            hash = hasher.finalize()
        }

        static func == (lhs: Paragraph, rhs: Paragraph) -> Bool {
            lhs.hash == rhs.hash && lhs.text == rhs.text
        }
    }

    private struct TokenDiff {
        var changes: [WordChange] = []
        var equalCount = 0
        var oldCount = 0
        var newCount = 0

        /// Half the longer side survived unchanged: enough to show as an edit rather
        /// than a paragraph swapped for another.
        var isSameParagraphEdited: Bool {
            equalCount * 2 >= max(oldCount, newCount)
        }

        mutating func append(_ change: WordChange) {
            // Merge with the previous change when both have the same fate.
            switch (changes.last, change) {
            case (.equal(let a)?, .equal(let b)):
                changes[changes.count - 1] = .equal(a + b)
            case (.inserted(let a)?, .inserted(let b)):
                changes[changes.count - 1] = .inserted(a + b)
            case (.removed(let a)?, .removed(let b)):
                changes[changes.count - 1] = .removed(a + b)
            default:
                changes.append(change)
            }
        }
    }

    private static func tokenDiff(old: [String], new: [String]) -> TokenDiff {
        var result = TokenDiff(oldCount: old.count, newCount: new.count)
        walk(new.difference(from: old), old: old, new: new) { change in
            switch change {
            case .removed(let index):
                result.append(.removed(old[index]))
            case .inserted(let index):
                result.append(.inserted(new[index]))
            case .equal(let index):
                result.equalCount += 1
                result.append(.equal(old[index]))
            }
        }
        return result
    }

    private enum LinearChange {
        case equal(oldIndex: Int)
        case removed(oldIndex: Int)
        case inserted(newIndex: Int)
    }

    /// Lays a difference out in document order by walking both collections with
    /// the removal offsets (in old) and insertion offsets (in new). Removals come
    /// before insertions at the same point, so a hunk always reads old-then-new.
    private static func walk<C: Collection>(
        _ difference: CollectionDifference<C.Element>,
        old: C,
        new: C,
        _ emit: (LinearChange) -> Void
    ) {
        let removals = difference.removals
        let insertions = difference.insertions
        var oldIndex = 0, newIndex = 0
        var nextRemoval = 0, nextInsertion = 0

        while oldIndex < old.count || newIndex < new.count {
            if nextRemoval < removals.count, removals[nextRemoval].offset == oldIndex {
                emit(.removed(oldIndex: oldIndex))
                oldIndex += 1
                nextRemoval += 1
            } else if nextInsertion < insertions.count, insertions[nextInsertion].offset == newIndex {
                emit(.inserted(newIndex: newIndex))
                newIndex += 1
                nextInsertion += 1
            } else {
                emit(.equal(oldIndex: oldIndex))
                oldIndex += 1
                newIndex += 1
            }
        }
    }
}

private extension CollectionDifference.Change {
    var offset: Int {
        switch self {
        case .insert(let offset, _, _), .remove(let offset, _, _): return offset
        }
    }
}
