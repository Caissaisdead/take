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

    @Test func editorFormHasNoBlankLines() {
        #expect(Prose.editorForm("One.\n\nTwo.\n\n\n\nThree.\n") == "One.\nTwo.\nThree.")
        #expect(Prose.editorForm("wrapped\nline\n\nnext") == "wrapped line\nnext")
        #expect(Prose.editorForm("") == "")
        #expect(Prose.editorForm("\n\n") == "")
    }

    @Test func everyLineBreakInTheEditorEndsAParagraph() {
        #expect(Prose.paragraphsByLine("One.\nTwo.") == ["One.", "Two."])
        #expect(Prose.paragraphsByLine("One.\r\nTwo.\rThree.") == ["One.", "Two.", "Three."])
        #expect(Prose.paragraphsByLine("One.  \n\n   \nTwo.\t\n") == ["One.", "Two."])
        #expect(Prose.paragraphsByLine("    Indented.") == ["    Indented."])
        #expect(Prose.paragraphsByLine("") == [])
        #expect(Prose.paragraphsByLine("\n \n") == [])
        #expect(Prose.join(Prose.paragraphsByLine("One.\nTwo.")) == "One.\n\nTwo.\n")
    }

    @Test func editorFormRoundTripsTheSample() throws {
        let sample = try ProseDiffTests.sample()
        let editor = Prose.editorForm(sample)
        #expect(!editor.contains("\n\n"))
        #expect(!editor.hasSuffix("\n"))
        #expect(Prose.join(Prose.paragraphsByLine(editor)) == sample)
        #expect(Prose.wordCount(editor) == Prose.wordCount(sample))
    }

    @Test func headAndTailKeepWholeParagraphs() {
        let text = "One two three.\n\nFour five.\n\nSix seven eight nine.\n"
        #expect(Prose.head(text, words: 5) == "One two three.\n\nFour five.\n")
        #expect(Prose.head(text, words: 4) == "One two three.\n")
        #expect(Prose.head(text, words: 100) == text)
        #expect(Prose.tail(text, words: 6) == "Four five.\n\nSix seven eight nine.\n")
        #expect(Prose.tail(text, words: 3) == "Six seven eight nine.\n")
        #expect(Prose.tail(text, words: 100) == text)
        // Never nothing: the nearest paragraph comes whole, however long.
        #expect(Prose.head(text, words: 0) == "One two three.\n")
        #expect(Prose.tail(text, words: 0) == "Six seven eight nine.\n")
        #expect(Prose.head("", words: 10) == "")
        #expect(Prose.tail("", words: 10) == "")
    }

    @Test func prefixWithinTokensKeepsWholeParagraphs() {
        let text = "One two three.\n\nFour five.\n\nSix seven eight nine.\n"
        let whole = Prose.prefix(text, withinTokens: 1_000)
        #expect(whole.kept == Prose.paragraphs(text))
        #expect(whole.total == 3)
        #expect(whole.whole)

        // The text costs about 15 tokens; a budget for two paragraphs keeps two.
        let cut = Prose.prefix(text, withinTokens: 10)
        #expect(cut.kept == ["One two three.", "Four five."])
        #expect(cut.total == 3)
        #expect(!cut.whole)

        // Not even the first fits: as much of it as does.
        let sliver = Prose.prefix(text, withinTokens: 2)
        #expect(sliver.kept == ["One tw"])
        #expect(sliver.total == 3)
        #expect(!sliver.whole)

        #expect(Prose.estimateTokens("") == 0)
        #expect(Prose.estimateTokens(String(repeating: "a", count: 350)) == 100)
        let empty = Prose.prefix("", withinTokens: 10)
        #expect(empty.kept.isEmpty && empty.total == 0 && empty.whole)
    }

    @Test func notesAreFoundAndTakenOut() {
        let text = "She left [[check the date]] at once.\n\n[[ whole paragraph is a note ]]\n\nHe stayed [[why?]] behind[[and then?]].\n"
        let notes = Prose.notes(in: text)
        #expect(notes.map(\.text) == ["check the date", "whole paragraph is a note", "why?", "and then?"])
        #expect(notes.map(\.paragraph) == [0, 1, 2, 2])
        #expect(notes[0].location == 9 && notes[0].length == 18)
        #expect(notes[3].location == 25)
        #expect(Prose.withoutNotes(text) == "She left at once.\n\nHe stayed behind.\n")
        #expect(Prose.withoutNotes("No notes here.\n") == "No notes here.\n")
        #expect(Prose.withoutNotes("[[only]]") == "")
        // A lone bracket, or an open note, is prose.
        #expect(Prose.notes(in: "[[not closed\n\n[x]\n").isEmpty)
        #expect(Prose.withoutNotes("[[not closed\n") == "[[not closed\n")
        #expect(Prose.wordCount(Prose.withoutNotes(text)) == 7)
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
