import Foundation
import Testing
@testable import ManuscriptKit

@Suite struct ManuscriptImportTests {
    @Test func markdownHeadingsMakeChaptersAndScenes() {
        let text = """
        # Pride and Prejudice

        ## Longbourn

        ### A Truth

        It is a truth.

        Universally.

        * * *

        Mr. Bennet replied.

        ## Netherfield

        The carriage turned in.

        ---

        Bingley met them.

        """
        let draft = ManuscriptImport.split(markdown: text, fallbackTitle: "Untitled")
        #expect(draft.title == "Pride and Prejudice")
        #expect(draft.chapters.map(\.title) == ["Longbourn", "Netherfield"])
        #expect(draft.chapters[0].scenes.map(\.title) == ["A Truth", "Scene 2"])
        #expect(draft.chapters[0].scenes[0].text == "It is a truth.\n\nUniversally.\n")
        #expect(draft.chapters[0].scenes[1].text == "Mr. Bennet replied.\n")
        #expect(draft.chapters[1].scenes.map(\.title) == ["Scene 1", "Scene 2"])
        #expect(draft.chapters[1].scenes[1].text == "Bingley met them.\n")
    }

    @Test func markdownWithoutHeadingsIsOneChapter() {
        let draft = ManuscriptImport.split(markdown: "One.\n\nTwo.\n\n* * *\n\nThree.\n", fallbackTitle: "From the folder")
        #expect(draft.title == "From the folder")
        #expect(draft.chapters.map(\.title) == ["Chapter 1"])
        #expect(draft.chapters[0].scenes.map(\.text) == ["One.\n\nTwo.\n", "Three.\n"])
        #expect(ManuscriptImport.split(markdown: "", fallbackTitle: "Empty").chapters.isEmpty)
        // A second top-level heading is a chapter, not another title.
        let two = ManuscriptImport.split(markdown: "# A\n\nText.\n\n# B\n\nMore.\n", fallbackTitle: "x")
        #expect(two.title == "A")
        #expect(two.chapters.map(\.title) == ["Chapter 1", "B"])
        // A heading-looking line with no space, or four marks, is prose.
        #expect(ManuscriptImport.split(markdown: "#hashtag\n\n#### four\n", fallbackTitle: "x").chapters[0].scenes[0].text == "#hashtag\n\n#### four\n")
    }

    @Test func filesMakeChaptersFromFoldersInNumberOrder() {
        let files: [(path: String, text: String)] = [
            ("10 Netherfield/01 The Ball.md", "Dancing.\n"),
            ("02 Longbourn/02-Bennet.md", "Replied."),
            ("02 Longbourn/01_A Truth.md", "Truth.\n\n\nMore.\n"),
            ("02 Longbourn/.DS_Store", ""),
        ]
        let draft = ManuscriptImport.draft(fromFiles: files.filter { !$0.path.hasSuffix(".DS_Store") }, title: "P&P")
        #expect(draft.chapters.map(\.title) == ["Longbourn", "Netherfield"])
        #expect(draft.chapters[0].scenes.map(\.title) == ["A Truth", "Bennet"])
        #expect(draft.chapters[0].scenes.map(\.text) == ["Truth.\n\nMore.\n", "Replied.\n"])
        #expect(draft.chapters[1].scenes.map(\.title) == ["The Ball"])

        let flat = ManuscriptImport.draft(fromFiles: [("b.md", "B."), ("a.txt", "A.")], title: "Flat")
        #expect(flat.chapters.map(\.title) == ["Chapter 1"])
        #expect(flat.chapters[0].scenes.map(\.title) == ["a", "b"])
        #expect(ManuscriptImport.cleanName("03") == "03")
        #expect(ManuscriptImport.cleanName(".hidden") == ".hidden")
    }

    @Test func aDraftBecomesAProjectInOneCommit() throws {
        try withTemporaryDirectory { url in
            let draft = Draft(title: "P&P", chapters: [
                Draft.Chapter(title: "Longbourn", scenes: [Draft.Scene(title: "A Truth", text: "Truth.\n"), Draft.Scene(title: "Reply", text: "Replied.\n")]),
                Draft.Chapter(title: "Netherfield", scenes: [Draft.Scene(title: "Ball", text: "Dancing.\n")]),
            ])
            let store = try ProjectStore.create(at: url, draft: draft, author: jane)
            let manuscript = try store.manifest()
            #expect(manuscript.title == "P&P")
            #expect(manuscript.chapters.map(\.title) == ["Longbourn", "Netherfield"])
            #expect(manuscript.chapters.map(\.folder) == ["chapters/01-longbourn", "chapters/02-netherfield"])
            #expect(manuscript.scenes.map(\.title) == ["A Truth", "Reply", "Ball"])
            #expect(manuscript.scenes.map(\.path) == ["chapters/01-longbourn/01-a-truth.md", "chapters/01-longbourn/02-reply.md", "chapters/02-netherfield/01-ball.md"])
            #expect(try store.sceneText(manuscript.scenes[2].id) == "Dancing.\n")
            let head = try store.repository.commit(try store.mainHead())
            #expect(head.message == "Import P&P")
            #expect(try store.repository.commit(head.parents[0]).parents.isEmpty)
            #expect(try store.history(of: manuscript.scenes[0].id).count == 1)
        }
    }

    @Test func aFolderWithAManifestAndNoRepositoryIsAdopted() throws {
        try withTemporaryDirectory { url in
            // A project made elsewhere, copied without its .git.
            let source = url.appendingPathComponent("source")
            let made = try ProjectStore.create(at: source, title: "P&P", author: jane)
            let scene = try made.addScene(title: "Opening", toChapter: nil, text: "Text.\n", synopsis: "Why.")
            let copy = url.appendingPathComponent("copy")
            try FileManager.default.copyItem(at: source, to: copy)
            try FileManager.default.removeItem(at: copy.appendingPathComponent(".git"))

            let adopted = try ProjectStore.adopt(at: copy, author: jane)
            #expect(try adopted.manifest().scene(scene.id)?.synopsis == "Why.")
            #expect(try adopted.sceneText(scene.id) == "Text.\n")
            let head = try adopted.repository.commit(try adopted.mainHead())
            #expect(head.message == "Adopt P&P")
            #expect(head.parents.isEmpty)
            #expect(try ProjectStore.open(at: copy, author: jane).manifest().title == "P&P")

            // Nothing to adopt without a manifest, or with a scene file missing.
            let bare = url.appendingPathComponent("bare")
            try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
            #expect(throws: ProjectStoreError.missingFile("manuscript.json")) { try ProjectStore.adopt(at: bare, author: jane) }
            try FileManager.default.removeItem(at: copy.appendingPathComponent(".git"))
            try FileManager.default.removeItem(at: copy.appendingPathComponent(scene.path))
            #expect(throws: ProjectStoreError.missingFile(scene.path)) { try ProjectStore.adopt(at: copy, author: jane) }
        }
    }
}
