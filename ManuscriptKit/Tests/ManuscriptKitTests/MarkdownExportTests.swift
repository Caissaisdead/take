import Foundation
import Testing
@testable import ManuscriptKit

@Suite struct MarkdownExportTests {
    private static let a1 = SceneRef(id: SceneID(), title: "A Truth", path: "chapters/01-a/01-a1.md")
    private static let a2 = SceneRef(id: SceneID(), title: "Mr. Bennet: Replies/Retorts", path: "chapters/01-a/02-a2.md")
    private static let b1 = SceneRef(id: SceneID(), title: "", path: "chapters/02-b/01-b1.md")
    private static let empty = SceneRef(id: SceneID(), title: "Nothing Yet", path: "chapters/02-b/02-empty.md")

    private static func manuscript(parts: Bool) -> (Manuscript, [SceneID: String]) {
        let a = Chapter(title: "Longbourn", folder: "chapters/01-a", scenes: [a1, a2])
        let b = Chapter(title: "Netherfield", folder: "chapters/02-b", scenes: [b1, empty])
        let texts: [SceneID: String] = [
            a1.id: "It is a truth.\n\nUniversally.\n",
            a2.id: "\"My dear Mr. Bennet.\"  \n\n\n\nHe had not.",
            b1.id: "The carriage turned in.\n",
            empty.id: "\n\n",
        ]
        if parts {
            return (Manuscript(title: "Pride & Prejudice", parts: [Part(title: "Volume One", chapters: [a]), Part(title: "", chapters: [b])]), texts)
        }
        return (Manuscript(title: "Pride & Prejudice", parts: [Part(title: "", chapters: [a, b])]), texts)
    }

    @Test func combinedWithoutPartsUsesChapterHeadingsAndSceneBreaks() throws {
        let (m, texts) = Self.manuscript(parts: false)
        let out = try MarkdownExport.combined(m) { texts[$0]! }
        #expect(out == """
        # Pride & Prejudice

        ## Longbourn

        It is a truth.

        Universally.

        * * *

        "My dear Mr. Bennet."

        He had not.

        ## Netherfield

        The carriage turned in.

        """)
    }

    @Test func combinedWithPartsNestsHeadingsAndNamesUntitledParts() throws {
        let (m, texts) = Self.manuscript(parts: true)
        let out = try MarkdownExport.combined(m) { texts[$0]! }
        #expect(out.hasPrefix("# Pride & Prejudice\n\n## Volume One\n\n### Longbourn\n\nIt is a truth."))
        #expect(out.contains("\n## Part 2\n\n### Netherfield\n\nThe carriage turned in.\n"))
    }

    @Test func filesAreNumberedNamedSafelyAndLedByTheCombinedDraft() throws {
        let (flat, texts) = Self.manuscript(parts: false)
        let files = try MarkdownExport.files(for: flat) { texts[$0]! }
        #expect(files.map(\.path) == [
            "Pride & Prejudice.md",
            "01 Longbourn/01 A Truth.md",
            "01 Longbourn/02 Mr. Bennet- Replies-Retorts.md",
            "02 Netherfield/01 Scene 1.md",
            "02 Netherfield/02 Nothing Yet.md",
        ])
        #expect(files[1].text == "It is a truth.\n\nUniversally.\n")
        #expect(files[2].text == "\"My dear Mr. Bennet.\"\n\nHe had not.\n")
        #expect(files[4].text == "")
        #expect(files[0].text == (try MarkdownExport.combined(flat) { texts[$0]! }))

        let (nested, _) = Self.manuscript(parts: true)
        #expect(try MarkdownExport.files(for: nested) { texts[$0]! }.map(\.path) == [
            "Pride & Prejudice.md",
            "01 Volume One/01 Longbourn/01 A Truth.md",
            "01 Volume One/01 Longbourn/02 Mr. Bennet- Replies-Retorts.md",
            "02 Part 2/02 Netherfield/01 Scene 1.md",
            "02 Part 2/02 Netherfield/02 Nothing Yet.md",
        ])
    }

    @Test func notesNeverLeaveWithTheDraft() throws {
        let scene = SceneRef(id: SceneID(), title: "Noted", path: "chapters/01-a/01-noted.md")
        let m = Manuscript(title: "P&P", parts: [Part(title: "", chapters: [Chapter(title: "One", folder: "chapters/01-a", scenes: [scene])])])
        let text = "It is a truth [[is it?]] acknowledged.\n\n[[cut this scene?]]\n"
        #expect(try MarkdownExport.combined(m) { _ in text } == "# P&P\n\n## One\n\nIt is a truth acknowledged.\n")
        #expect(try MarkdownExport.files(for: m) { _ in text }[1].text == "It is a truth acknowledged.\n")
    }

    @Test func fileNamesNeverHideOrEscapeTheFolder() {
        #expect(MarkdownExport.fileName("../etc", fallback: "x") == "-etc")
        #expect(MarkdownExport.fileName("...", fallback: "x") == "x")
        #expect(MarkdownExport.fileName("  ", fallback: "Scene 3") == "Scene 3")
        #expect(MarkdownExport.fileName("a\u{0}b\tc", fallback: "x") == "abc")
        #expect(MarkdownExport.fileName(String(repeating: "é", count: 200), fallback: "x").count == 120)
    }

    @Test func storeExportReadsMainAndNothingElse() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let chapter = try store.addChapter(title: "One", toPart: nil)
            let scene = try store.addScene(title: "Opening", toChapter: chapter.id, text: "Main text.\n")
            let take = try store.createTake(for: scene.id, name: "Alt")
            try store.saveTake(take, text: "Take text.\n")

            let files = try store.exportMarkdown()
            #expect(files.map(\.path) == ["P&P.md", "01 One/01 Opening.md"])
            #expect(files[1].text == "Main text.\n")
            #expect(files[0].text == "# P&P\n\n## One\n\nMain text.\n")
        }
    }
}
