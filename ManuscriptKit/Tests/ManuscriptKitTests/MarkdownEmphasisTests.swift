import Foundation
import Testing
@testable import ManuscriptKit

@Suite struct MarkdownEmphasisTests {
    private typealias Run = (location: Int, length: Int, trait: MarkdownEmphasis.Trait)

    /// Runs as plain tuples, sorted by where they start, so a test can compare them.
    private func strip(_ paragraph: String) -> (text: String, runs: [Run]) {
        let stripped = MarkdownEmphasis.strip(paragraph)
        let runs = stripped.runs
            .map { (location: $0.range.location, length: $0.range.length, trait: $0.trait) }
            .sorted { ($0.location, $0.length) < ($1.location, $1.length) }
        return (stripped.text, runs)
    }

    private func same(_ a: [Run], _ b: [Run]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.location == $1.location && $0.length == $1.length && $0.trait == $1.trait }
    }

    @Test func plainEmphasisLosesItsMarkers() {
        let bold = strip("A **bold** word.")
        #expect(bold.text == "A bold word.")
        #expect(same(bold.runs, [(2, 4, .bold)]))

        let italic = strip("An *italic* word.")
        #expect(italic.text == "An italic word.")
        #expect(same(italic.runs, [(3, 6, .italic)]))

        let underscore = strip("An _italic_ word.")
        #expect(underscore.text == "An italic word.")
        #expect(same(underscore.runs, [(3, 6, .italic)]))
    }

    @Test func nestedEmphasisKeepsBothRuns() {
        let italicInBold = strip("**a *b* c**")
        #expect(italicInBold.text == "a b c")
        #expect(same(italicInBold.runs, [(0, 5, .bold), (2, 1, .italic)]))

        let boldInItalic = strip("*a **b** c*")
        #expect(boldInItalic.text == "a b c")
        #expect(same(boldInItalic.runs, [(0, 5, .italic), (2, 1, .bold)]))
    }

    @Test func runsAfterAMatchMoveWithTheText() {
        let two = strip("*a* b *c*")
        #expect(two.text == "a b c")
        #expect(same(two.runs, [(0, 1, .italic), (4, 1, .italic)]))

        let mixed = strip("**a** and *b* and _c_")
        #expect(mixed.text == "a and b and c")
        #expect(same(mixed.runs, [(0, 1, .bold), (6, 1, .italic), (12, 1, .italic)]))
    }

    @Test func whatIsNotEmphasisIsLeftAlone() {
        #expect(strip("**a *b").text == "**a *b")
        #expect(strip("**a *b").runs.isEmpty)
        #expect(strip("snake_case_name and 2 * 3 * 4").text == "snake_case_name and 2 * 3 * 4")
        #expect(strip("** not bold **").text == "** not bold **")
        #expect(strip("").text == "")
        #expect(strip("").runs.isEmpty)
    }

    @Test func sceneBreaks() {
        #expect(MarkdownEmphasis.isSceneBreak("* * *"))
        #expect(MarkdownEmphasis.isSceneBreak("  ---  "))
        #expect(!MarkdownEmphasis.isSceneBreak("***"))
        #expect(!MarkdownEmphasis.isSceneBreak("* * * and on"))
        #expect(!MarkdownEmphasis.isSceneBreak(""))
    }

    /// The editor and the exports read the same patterns; the sample scene's
    /// underscored italics must survive a strip whole.
    @Test func sampleSceneItalicsStrip() throws {
        let sample = try ProseDiffTests.sample()
        var italics = 0
        for paragraph in Prose.paragraphs(sample) {
            let stripped = MarkdownEmphasis.strip(paragraph)
            #expect(!stripped.text.contains("_"), "\(paragraph)")
            italics += stripped.runs.count
            for run in stripped.runs {
                #expect(run.range.location + run.range.length <= (stripped.text as NSString).length)
            }
        }
        #expect(italics > 0)
    }
}
