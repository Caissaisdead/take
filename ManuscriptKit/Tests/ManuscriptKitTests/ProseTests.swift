import Testing
@testable import ManuscriptKit

@Suite struct ProseTests {
    @Test func paragraphsSplitOnBlankLines() {
        #expect(Prose.paragraphs("One.\n\nTwo.\n\n\n\nThree.\n") == ["One.", "Two.", "Three."])
        #expect(Prose.paragraphs("") == [])
        #expect(Prose.paragraphs("\n\n\n") == [])
        #expect(Prose.paragraphs("Only one, no newline") == ["Only one, no newline"])
    }

    @Test func paragraphsNormaliseLineEndings() {
        #expect(Prose.paragraphs("One.\r\n\r\nTwo.\r\n") == ["One.", "Two."])
        #expect(Prose.paragraphs("One.\r\rTwo.") == ["One.", "Two."])
        #expect(Prose.paragraphs("One.\r\n\nTwo.\n\r\nThree.") == ["One.", "Two.", "Three."])
        #expect(Prose.paragraphs("wrapped\r\nline") == ["wrapped line"])
    }

    @Test func paragraphsJoinHardWraps() {
        let wrapped = "It is a truth universally\nacknowledged, that a single man\nin possession of a good fortune\n\nmust be in want of a wife."
        #expect(Prose.paragraphs(wrapped) == [
            "It is a truth universally acknowledged, that a single man in possession of a good fortune",
            "must be in want of a wife.",
        ])
    }

    @Test func whitespaceOnlyLinesAreBlank() {
        #expect(Prose.paragraphs("One.\n   \nTwo.\n\t\n \t \nThree.") == ["One.", "Two.", "Three."])
        #expect(Prose.paragraphs("   \n\t\n") == [])
    }

    @Test func trailingWhitespaceIsTrimmed() {
        #expect(Prose.paragraphs("One.   \n\nTwo.\t\n") == ["One.", "Two."])
        #expect(Prose.paragraphs("wrapped  \nline \n") == ["wrapped line"])
    }

    @Test func internalAndLeadingWhitespaceSurvive() {
        #expect(Prose.paragraphs("End.  Next sentence.") == ["End.  Next sentence."])
        #expect(Prose.paragraphs("    Indented opening.") == ["    Indented opening."])
        #expect(Prose.paragraphs("a\tb") == ["a\tb"])
    }

    @Test func joinForms() {
        #expect(Prose.join([]) == "")
        #expect(Prose.join(["One."]) == "One.\n")
        #expect(Prose.join(["One.", "Two."]) == "One.\n\nTwo.\n")
    }

    @Test func normalizeIsIdempotent() {
        let messy = "One.  \r\n  \r\nTwo\r\nwrapped.\n\n\n\nThree.\t"
        let once = Prose.normalize(messy)
        #expect(once == "One.\n\nTwo wrapped.\n\nThree.\n")
        #expect(Prose.normalize(once) == once)
        #expect(Prose.paragraphs(once) == Prose.paragraphs(messy))
        #expect(Prose.normalize("") == "")
        #expect(Prose.normalize("\n\n  \n") == "")
    }

    @Test func wordCount() {
        #expect(Prose.wordCount("") == 0)
        #expect(Prose.wordCount("   \n\t") == 0)
        #expect(Prose.wordCount("one") == 1)
        #expect(Prose.wordCount("  one two\tthree\n\nfour  ") == 4)
        #expect(Prose.wordCount("well-known — “quoted”") == 3)
        #expect(Prose.wordCount("One.\r\nTwo.\rThree.") == 3)
    }

    @Test(arguments: [
        "",
        " ",
        "   ",
        "one",
        "  leading spaces",
        "trailing spaces   ",
        "\ttabs\there\t",
        "double  spaced   words",
        "naïve café 日本語 🙂 done",
        "“Hello,” she said — and left.",
        "punctuation... ellipsis?! yes.",
        "mixed \t whitespace \u{00A0} nbsp",
        "ends with a newline\n",
        "\nstarts with one",
        "\r\n",
    ])
    func tokensRoundTrip(_ paragraph: String) {
        let tokens = Prose.tokens(paragraph)
        #expect(tokens.joined() == paragraph)
        #expect(tokens.allSatisfy { !$0.isEmpty })
    }

    @Test func tokensShape() {
        #expect(Prose.tokens("") == [])
        #expect(Prose.tokens("one") == ["one"])
        #expect(Prose.tokens("one two") == ["one ", "two"])
        #expect(Prose.tokens("one  two ") == ["one  ", "two "])
        #expect(Prose.tokens("  one") == ["  ", "one"])
        #expect(Prose.tokens("   ") == ["   "])
        #expect(Prose.tokens("\tone\ttwo") == ["\t", "one\t", "two"])
        #expect(Prose.tokens("“Hello,” she said.") == ["“Hello,” ", "she ", "said."])
        #expect(Prose.tokens("naïve café") == ["naïve ", "café"])
    }
}
