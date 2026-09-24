import Foundation
import Testing
@testable import ManuscriptKit

@Suite struct ManuscriptSearchTests {
    @Test func hitsIgnoreCaseAndAccentsAndCountEveryOne() {
        let text = "Mr. Bingley came. Bingley again.\n\nNo one here.\n\nCafé, then café.\n"
        let hits = ManuscriptSearch.hits(of: "bingley", in: text)
        #expect(hits == [.init(paragraph: 0, location: 4, length: 7), .init(paragraph: 0, location: 18, length: 7)])
        #expect(ManuscriptSearch.hits(of: "cafe", in: text) == [.init(paragraph: 2, location: 0, length: 4), .init(paragraph: 2, location: 11, length: 4)])
        #expect(ManuscriptSearch.hits(of: "  ", in: text).isEmpty)
        #expect(ManuscriptSearch.hits(of: "Darcy", in: text).isEmpty)
        // Overlapping occurrences count once each, moving on past the hit.
        #expect(ManuscriptSearch.hits(of: "aa", in: "aaaa\n").count == 2)
        // Locations are what a text view counts: an emoji is two.
        #expect(ManuscriptSearch.hits(of: "x", in: "🙂x\n") == [.init(paragraph: 0, location: 2, length: 1)])
    }

    @Test func editorRangeSkipsBlankLines() {
        let editor = "One two.\n\nThree four.\n  \nFive."
        let first = Prose.editorRange(paragraph: 0, location: 4, length: 3, in: editor)
        #expect(first?.location == 4 && first?.length == 3)
        let second = Prose.editorRange(paragraph: 1, location: 6, length: 4, in: editor)
        #expect(second?.location == 16 && second?.length == 4)
        let third = Prose.editorRange(paragraph: 2, location: 0, length: 5, in: editor)
        #expect(third?.location == 25 && third?.length == 5)
        #expect(Prose.editorRange(paragraph: 3, location: 0, length: 1, in: editor) == nil)
        // Straight from stored form, with no blank lines at all.
        let plain = Prose.editorForm("One two.\n\nThree four.\n")
        #expect(Prose.editorRange(paragraph: 1, location: 0, length: 5, in: plain)?.location == 9)
    }

    @Test func storeSearchesMainAndThenTakes() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let one = try store.addScene(title: "One", toChapter: nil, text: "Bingley arrives.\n\nNothing.\n")
            let two = try store.addScene(title: "Two", toChapter: nil, text: "Nothing.\n\nAnd Bingley leaves; Bingley!\n")
            let take = try store.saveTake(try store.createTake(for: one.id, name: "Alt"), text: "BINGLEY does not arrive.\n")

            let main = try store.search("bingley", includingTakes: false)
            #expect(main.map(\.scene) == [one.id, two.id, two.id])
            #expect(main.map(\.paragraph) == [0, 1, 1])
            #expect(main.map(\.location) == [0, 4, 20])
            #expect(main[0].text == "Bingley arrives.")
            #expect(main.allSatisfy { $0.take == nil })

            let all = try store.search("Bingley", includingTakes: true)
            #expect(all.count == 4)
            #expect(all[1].take?.id == take.id)
            #expect(all[1].text == "BINGLEY does not arrive.")
            #expect(try store.search("", includingTakes: true).isEmpty)
            #expect(try store.search("Darcy", includingTakes: true).isEmpty)
        }
    }
}
