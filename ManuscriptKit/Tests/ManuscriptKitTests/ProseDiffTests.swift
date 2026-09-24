import Foundation
import Testing
@testable import ManuscriptKit

@Suite struct ProseDiffTests {
    @Test func identicalTextsAreAllEqual() {
        let text = "One.\n\nTwo.\n\nThree.\n"
        let diff = ProseDiffer.diff(old: text, new: text)
        #expect(diff.segments == [.equal("One."), .equal("Two."), .equal("Three.")])
        #expect(!diff.hasChanges)
        #expect(diff.summary == .init(paragraphsChanged: 0, wordsAdded: 0, wordsRemoved: 0))
    }

    @Test func identicalAfterNormalisationIsUnchanged() {
        let diff = ProseDiffer.diff(old: "One.\r\n\r\nTwo\r\nwrapped.  \r\n", new: "One.\n\nTwo wrapped.\n")
        #expect(!diff.hasChanges)
    }

    @Test func oneWordChanged() {
        let old = "First paragraph.\n\nThe quick brown fox jumps.\n\nLast paragraph.\n"
        let new = "First paragraph.\n\nThe quick red fox jumps.\n\nLast paragraph.\n"
        let diff = ProseDiffer.diff(old: old, new: new)
        #expect(diff.hasChanges)
        #expect(diff.segments == [
            .equal("First paragraph."),
            .changed(old: "The quick brown fox jumps.", new: "The quick red fox jumps.", words: [
                .equal("The quick "), .removed("brown "), .inserted("red "), .equal("fox jumps."),
            ]),
            .equal("Last paragraph."),
        ])
        #expect(diff.summary == .init(paragraphsChanged: 1, wordsAdded: 1, wordsRemoved: 1))
    }

    @Test func paragraphInsertedInTheMiddle() {
        let diff = ProseDiffer.diff(old: "One.\n\nThree.\n", new: "One.\n\nTwo two.\n\nThree.\n")
        #expect(diff.segments == [.equal("One."), .inserted("Two two."), .equal("Three.")])
        #expect(diff.summary == .init(paragraphsChanged: 1, wordsAdded: 2, wordsRemoved: 0))
    }

    @Test func paragraphRemoved() {
        let diff = ProseDiffer.diff(old: "One.\n\nTwo two.\n\nThree.\n", new: "One.\n\nThree.\n")
        #expect(diff.segments == [.equal("One."), .removed("Two two."), .equal("Three.")])
        #expect(diff.summary == .init(paragraphsChanged: 1, wordsAdded: 0, wordsRemoved: 2))
    }

    @Test func swappedParagraphsAreMovedNotChanged() {
        let a = "Alpha stands first and says its piece."
        let b = "Beta follows with a different thought entirely."
        let diff = ProseDiffer.diff(old: Prose.join([a, b]), new: Prose.join([b, a]))
        let kinds = diff.segments.map(Kind.init)
        #expect(!kinds.contains(.changed))
        #expect(kinds.filter { $0 == .removed }.count == 1)
        #expect(kinds.filter { $0 == .inserted }.count == 1)
        #expect(kinds.filter { $0 == .equal }.count == 1)
        #expect(diff.summary.paragraphsChanged == 2)
    }

    @Test func rewrittenParagraphIsRemovedAndInserted() {
        let old = "One.\n\nThe cat sat on the mat.\n\nThree.\n"
        let new = "One.\n\nEntirely different words appear here now.\n\nThree.\n"
        let diff = ProseDiffer.diff(old: old, new: new)
        #expect(diff.segments == [
            .equal("One."),
            .removed("The cat sat on the mat."),
            .inserted("Entirely different words appear here now."),
            .equal("Three."),
        ])
        #expect(diff.summary == .init(paragraphsChanged: 2, wordsAdded: 6, wordsRemoved: 6))
    }

    @Test func similarityThresholdIsHalfTheLongerSide() {
        // 3 of 6 old tokens survive: exactly half, so still an edit.
        let atThreshold = ProseDiffer.diff(old: "a b c d e f\n", new: "a b c x y z\n")
        #expect(atThreshold.segments.map(Kind.init) == [.changed])
        // 2 of 6 survive: below half, so a replacement.
        let below = ProseDiffer.diff(old: "a b c d e f\n", new: "a b x y z w\n")
        #expect(below.segments.map(Kind.init) == [.removed, .inserted])
        // A long insertion into a short paragraph is judged against the longer side.
        let grown = ProseDiffer.diff(old: "a b\n", new: "a b c d e f g\n")
        #expect(grown.segments.map(Kind.init) == [.removed, .inserted])
    }

    @Test func hunkPairsByOrderAndLeavesTheRest() {
        let a = "Opening paragraph stays exactly as it was."
        let r1 = "The first rewritten paragraph changes one word here."
        let r2 = "The second rewritten paragraph also changes one word."
        let n3 = "A brand new paragraph follows the two edits."
        let z = "Closing paragraph stays exactly as it was."
        let r1New = r1.replacingOccurrences(of: "one", with: "a")
        let r2New = r2.replacingOccurrences(of: "one", with: "a")

        let diff = ProseDiffer.diff(old: Prose.join([a, r1, r2, z]), new: Prose.join([a, r1New, r2New, n3, z]))
        #expect(diff.segments.map(Kind.init) == [.equal, .changed, .changed, .inserted, .equal])
        guard case .changed(let old1, let new1, _) = diff.segments[1],
              case .changed(let old2, let new2, _) = diff.segments[2],
              case .inserted(let extra) = diff.segments[3] else { return }
        #expect(old1 == r1 && new1 == r1New)
        #expect(old2 == r2 && new2 == r2New)
        #expect(extra == n3)
        #expect(diff.summary == .init(paragraphsChanged: 3, wordsAdded: 2 + 8, wordsRemoved: 2))
    }

    @Test func hunkWithMoreRemovedThanInserted() {
        let r1 = "The first rewritten paragraph changes one word here."
        let r2 = "The second rewritten paragraph also changes one word."
        let r3 = "The third paragraph is simply gone."
        let diff = ProseDiffer.diff(
            old: Prose.join([r1, r2, r3]),
            new: Prose.join([r1.replacingOccurrences(of: "one", with: "a"), r2.replacingOccurrences(of: "one", with: "a")])
        )
        #expect(diff.segments.map(Kind.init) == [.changed, .changed, .removed])
    }

    @Test func emptyOld() {
        let diff = ProseDiffer.diff(old: "", new: "One.\n\nTwo two.\n")
        #expect(diff.segments == [.inserted("One."), .inserted("Two two.")])
        #expect(diff.summary == .init(paragraphsChanged: 2, wordsAdded: 3, wordsRemoved: 0))
    }

    @Test func emptyNew() {
        let diff = ProseDiffer.diff(old: "One.\n\nTwo two.\n", new: "")
        #expect(diff.segments == [.removed("One."), .removed("Two two.")])
        #expect(diff.summary == .init(paragraphsChanged: 2, wordsAdded: 0, wordsRemoved: 3))
    }

    @Test func bothEmpty() {
        let diff = ProseDiffer.diff(old: "", new: "\n\n  \n")
        #expect(diff.segments.isEmpty)
        #expect(!diff.hasChanges)
    }

    @Test func summaryCountsWordsNotWhitespaceTokens() {
        let inserted = ProseDiffer.diff(old: "One.\n", new: "One.\n\n    Indented two.\n")
        #expect(inserted.segments == [.equal("One."), .inserted("    Indented two.")])
        #expect(inserted.summary == .init(paragraphsChanged: 1, wordsAdded: 2, wordsRemoved: 0))

        let indented = ProseDiffer.diff(old: "a b c d\n", new: "    a b c d\n")
        #expect(indented.segments.map(Kind.init) == [.changed])
        #expect(indented.summary == .init(paragraphsChanged: 1, wordsAdded: 0, wordsRemoved: 0))
    }

    @Test func wordDiffMergesRuns() {
        #expect(ProseDiffer.wordDiff(old: "a b c d e", new: "a x y d e") == [
            .equal("a "), .removed("b c "), .inserted("x y "), .equal("d e"),
        ])
        #expect(ProseDiffer.wordDiff(old: "same words", new: "same words") == [.equal("same words")])
        #expect(ProseDiffer.wordDiff(old: "", new: "") == [])
        #expect(ProseDiffer.wordDiff(old: "", new: "a b") == [.inserted("a b")])
        #expect(ProseDiffer.wordDiff(old: "a b", new: "") == [.removed("a b")])
        #expect(ProseDiffer.wordDiff(old: "a b", new: "a b c") == [.equal("a "), .removed("b"), .inserted("b c")])
    }

    @Test func wordDiffRoundTrips() {
        let old = "The quick brown fox jumps over the lazy dog."
        let new = "The slow brown fox leaps over the very lazy dog!"
        let words = ProseDiffer.wordDiff(old: old, new: new)
        let oldSide = words.compactMap { change -> String? in if case .inserted = change { return nil }; return change.text }.joined()
        let newSide = words.compactMap { change -> String? in if case .removed = change { return nil }; return change.text }.joined()
        #expect(oldSide == old)
        #expect(newSide == new)
    }

    // The sample scene: 5,017 words in 122 paragraphs.

    static let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Spike/Resources/sample-scene.md")

    static func sample() throws -> String {
        try String(contentsOf: sampleURL, encoding: .utf8)
    }

    @Test func sampleSceneShape() throws {
        let text = try Self.sample()
        #expect(Prose.paragraphs(text).count == 122)
        #expect(Prose.wordCount(text) == 5017)
        #expect(Prose.normalize(text) == text)
    }

    @Test func oneWordChangedInSampleIsFast() throws {
        let old = try Self.sample()
        var paragraphs = Prose.paragraphs(old)
        paragraphs[60] = changingWord(at: 5, in: paragraphs[60])
        let new = Prose.join(paragraphs)

        var diff = ProseDiff(segments: [])
        let elapsed = fastest(of: 3) { diff = ProseDiffer.diff(old: old, new: new) }
        print("prose diff, one word changed in 5,017 words: \(elapsed)")

        #expect(elapsed < .milliseconds(100), "target is 20 ms")
        #expect(diff.segments.count == 122)
        #expect(diff.segments.map(Kind.init).filter { $0 == .changed }.count == 1)
        #expect(diff.summary == .init(paragraphsChanged: 1, wordsAdded: 1, wordsRemoved: 1))
    }

    @Test func everyParagraphChangedInSampleIsFast() throws {
        let old = try Self.sample()
        let paragraphs = Prose.paragraphs(old)
        let new = Prose.join(paragraphs.map { changingWord(at: 3, in: $0) })

        var diff = ProseDiff(segments: [])
        let elapsed = fastest(of: 3) { diff = ProseDiffer.diff(old: old, new: new) }
        print("prose diff, every paragraph changed in 5,017 words: \(elapsed)")

        #expect(elapsed < .milliseconds(1000), "target is 200 ms")
        let kinds = diff.segments.map(Kind.init)
        #expect(!kinds.contains(.equal))
        // One paragraph of the scene is a single word, so with that word changed it
        // cannot reach the similarity threshold and falls back to removed + inserted.
        #expect(kinds.filter { $0 == .changed }.count == 121)
        #expect(diff.summary == .init(paragraphsChanged: 123, wordsAdded: 122, wordsRemoved: 122))
    }

    private enum Kind: Equatable {
        case equal, inserted, removed, changed

        init(_ segment: ProseDiff.Segment) {
            switch segment {
            case .equal: self = .equal
            case .inserted: self = .inserted
            case .removed: self = .removed
            case .changed: self = .changed
            }
        }
    }

    /// Replaces the word of one token, keeping the whitespace it carries.
    private func changingWord(at index: Int, in paragraph: String) -> String {
        var tokens = Prose.tokens(paragraph)
        let i = min(index, tokens.count - 1)
        tokens[i] = "altered" + tokens[i].drop(while: { !$0.isWhitespace })
        return tokens.joined()
    }

    private func fastest(of runs: Int, _ body: () -> Void) -> Duration {
        let clock = ContinuousClock()
        var best = Duration.seconds(Int.max / 2)
        for _ in 0..<runs { best = min(best, clock.measure(body)) }
        return best
    }
}

private extension WordChange {
    var text: String {
        switch self {
        case .equal(let s), .inserted(let s), .removed(let s): return s
        }
    }
}
