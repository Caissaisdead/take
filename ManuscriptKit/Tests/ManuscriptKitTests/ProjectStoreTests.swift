import Foundation
import Testing
@testable import ManuscriptKit

private let opening = "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.\n\nHowever little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families.\n"

/// Runs the system git in `directory` and returns everything it printed.
private func git(_ arguments: String..., in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: output, as: UTF8.self)
}

@Suite struct ProjectStoreTests {
    @Test func createWritesManifestAndRootCommitOnMain() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "Pride and Prejudice", author: jane)

            let onDisk = try Data(contentsOf: url.appendingPathComponent("manuscript.json"))
            let decoded = try JSONDecoder().decode(Manuscript.self, from: onDisk)
            #expect(decoded == Manuscript(title: "Pride and Prejudice"))
            #expect(String(decoding: onDisk, as: UTF8.self).hasSuffix("}\n"))
            #expect(try store.manifest() == decoded)

            let head = try store.mainHead()
            let root = try store.repository.commit(head)
            #expect(root.parents.isEmpty)
            #expect(root.message == "Begin Pride and Prejudice")
            #expect(root.author.name == "Jane Austen")
            #expect(try store.repository.resolve("HEAD") == head)
            #expect(try store.repository.entry(atPath: "manuscript.json", inTree: root.tree) != nil)

            let reopened = try ProjectStore.open(at: url, author: jane)
            #expect(try reopened.manifest().title == "Pride and Prejudice")
        }
    }

    @Test func openRefusesAFolderThatIsNotAProject() throws {
        try withTemporaryDirectory { url in
            _ = try Repository.create(at: url)
            #expect(throws: (any Error).self) { try ProjectStore.open(at: url, author: jane) }
        }
    }

    @Test func addScenePathsAreNumberedSluggedAndUnique() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let first = try store.addScene(title: "A Truth Universally Acknowledged!", toChapter: nil, text: opening)
            #expect(first.path == "chapters/01-chapter-1/01-a-truth-universally-acknowledged.md")
            #expect(first.title == "A Truth Universally Acknowledged!")
            #expect(try Data(contentsOf: url.appendingPathComponent(first.path)) == Data(opening.utf8))
            #expect(try store.sceneText(first.id) == opening)

            // The first scene of a bare manuscript makes an untitled part and a first chapter.
            let manuscript = try store.manifest()
            #expect(manuscript.parts.map(\.title) == [""])
            #expect(manuscript.chapters.map(\.title) == ["Chapter 1"])
            #expect(manuscript.chapters[0].folder == "chapters/01-chapter-1")
            #expect(manuscript.chapters[0].scenes == [first])
            #expect(try store.repository.commit(try store.mainHead()).message == "Add A Truth Universally Acknowledged!")

            let second = try store.addScene(title: "Mr. Bingley’s £5,000 — Netherfield", toChapter: manuscript.chapters[0].id, text: "Text.\n")
            #expect(second.path == "chapters/01-chapter-1/02-mr-bingley-s-5-000-netherfield.md")
            let blank = try store.addScene(title: "¡¿!?", toChapter: nil, text: "Text.\n")
            #expect(blank.path == "chapters/01-chapter-1/03-scene.md")

            // A file numbered 02 is already in the tree, so a re-added second scene steps aside.
            var trimmed = try store.manifest()
            try trimmed.remove(scene: second.id)
            try trimmed.remove(scene: blank.id)
            try store.saveManifest(trimmed, message: "Drop two scenes")
            let again = try store.addScene(title: "Mr Bingley s 5 000 Netherfield", toChapter: nil, text: "Again.\n")
            #expect(again.path == "chapters/01-chapter-1/02-mr-bingley-s-5-000-netherfield-2.md")

            // A new chapter is numbered after every chapter so far, and a scene with no chapter goes to the last one.
            let netherfield = try store.addChapter(title: "Netherfield", toPart: nil)
            #expect(netherfield.folder == "chapters/02-netherfield")
            #expect(try store.repository.commit(try store.mainHead()).message == "Add chapter Netherfield")
            let inSecond = try store.addScene(title: "The Ball", toChapter: netherfield.id, text: "Dancing.\n")
            #expect(inSecond.path == "chapters/02-netherfield/01-the-ball.md")
            #expect(try store.addScene(title: "After", toChapter: nil, text: "Late.\n").path == "chapters/02-netherfield/02-after.md")
            // Numbered by count, placed by index.
            let between = try store.addScene(title: "Between", toChapter: netherfield.id, at: 1, text: "Mid.\n")
            #expect(between.path == "chapters/02-netherfield/03-between.md")
            #expect(try store.manifest().chapter(netherfield.id)?.scenes.map(\.title) == ["The Ball", "Between", "After"])

            #expect(throws: ProjectStoreError.unknownChapter(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)) {
                try store.addScene(title: "Lost", toChapter: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, text: "")
            }
        }
    }

    @Test func chaptersAreNumberedAcrossPartsAndFoldersNeverCollide() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let one = try store.addPart(title: "Volume One")
            let two = try store.addPart(title: "Volume Two")
            #expect(try store.manifest().parts.map(\.title) == ["Volume One", "Volume Two"])
            #expect(try store.repository.commit(try store.mainHead()).message == "Add part Volume Two")

            let longbourn = try store.addChapter(title: "Longbourn", toPart: one.id)
            let london = try store.addChapter(title: "London", toPart: two.id)
            let meryton = try store.addChapter(title: "Meryton", toPart: one.id)
            #expect([longbourn, london, meryton].map(\.folder) == ["chapters/01-longbourn", "chapters/02-london", "chapters/03-meryton"])
            #expect(try store.manifest().part(one.id)?.chapters.map(\.id) == [longbourn.id, meryton.id])
            #expect(try store.manifest().part(two.id)?.chapters.map(\.id) == [london.id])
            // A chapter with no part goes to the last one; an untitled one still gets a folder.
            let untitled = try store.addChapter(title: "   ", toPart: nil)
            #expect(untitled.folder == "chapters/04-chapter")
            #expect(try store.manifest().part(two.id)?.chapters.map(\.id) == [london.id, untitled.id])
            #expect(try store.repository.commit(try store.mainHead()).message == "Add chapter (untitled)")

            // Removing the first chapter leaves three, so the next is numbered 04
            // again and must step aside from the folder still in the manifest.
            try store.remove(chapter: longbourn.id)
            #expect(try store.addChapter(title: "Chapter", toPart: nil).folder == "chapters/04-chapter-2")

            #expect(throws: ProjectStoreError.unknownPart(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)) {
                try store.addChapter(title: "Lost", toPart: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
            }
        }
    }

    @Test func renamesAndMovesChangeOnlyTheManifest() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let part = try store.addPart(title: "One")
            let a = try store.addChapter(title: "A", toPart: part.id)
            let b = try store.addChapter(title: "B", toPart: part.id)
            let a1 = try store.addScene(title: "A1", toChapter: a.id, text: "A1.\n")
            let a2 = try store.addScene(title: "A2", toChapter: a.id, text: "A2.\n")
            let b1 = try store.addScene(title: "B1", toChapter: b.id, text: "B1.\n")
            let tree = try store.repository.commit(try store.mainHead()).tree

            try store.rename(scene: a1.id, to: "Longbourn")
            try store.rename(chapter: a.id, to: "Opening")
            try store.rename(part: part.id, to: "Volume One")
            var manuscript = try store.manifest()
            #expect(manuscript.scene(a1.id)?.title == "Longbourn")
            #expect(manuscript.scene(a1.id)?.path == a1.path)
            #expect(manuscript.chapter(a.id)?.title == "Opening")
            #expect(manuscript.chapter(a.id)?.folder == a.folder)
            #expect(manuscript.part(part.id)?.title == "Volume One")
            #expect(try store.repository.commit(try store.mainHead()).message == "Rename part One to Volume One")

            try store.move(scene: a1.id, toChapter: b.id, at: 0)
            try store.move(scene: a2.id, toChapter: b.id, at: 99)
            manuscript = try store.manifest()
            #expect(manuscript.chapter(a.id)?.scenes.isEmpty == true)
            #expect(manuscript.chapter(b.id)?.scenes.map(\.id) == [a1.id, b1.id, a2.id])
            #expect(try store.repository.commit(try store.mainHead()).message == "Move A2")

            let two = try store.addPart(title: "Two")
            try store.move(chapter: b.id, toPart: two.id, at: 0)
            try store.move(part: two.id, to: 0)
            manuscript = try store.manifest()
            #expect(manuscript.parts.map(\.id) == [two.id, part.id])
            #expect(manuscript.part(two.id)?.chapters.map(\.id) == [b.id])
            #expect(manuscript.part(part.id)?.chapters.map(\.id) == [a.id])

            // Every file is exactly where it was.
            for scene in [a1, a2, b1] {
                #expect(try store.repository.entry(atPath: scene.path, inTree: try store.repository.commit(try store.mainHead()).tree)
                    == (try store.repository.entry(atPath: scene.path, inTree: tree)))
                #expect(try store.sceneText(scene.id) == "\(scene.title).\n")
            }
            #expect(try git("status", "--porcelain", in: url) == "")
            #expect(try store.history(of: a1.id).map(\.message) == ["Add A1"])

            let ghost = SceneID()
            #expect(throws: ProjectStoreError.unknownScene(ghost)) { try store.rename(scene: ghost, to: "X") }
        }
    }

    @Test func removeDropsTheFilesAndKeepsTheHistory() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let part = try store.addPart(title: "One")
            let a = try store.addChapter(title: "A", toPart: part.id)
            let a1 = try store.addScene(title: "A1", toChapter: a.id, text: "A1.\n")
            let a2 = try store.addScene(title: "A2", toChapter: a.id, text: "A2.\n")
            let b = try store.addChapter(title: "B", toPart: part.id)
            let b1 = try store.addScene(title: "B1", toChapter: b.id, text: "B1.\n")
            let take = try store.saveTake(try store.createTake(for: a1.id, name: "Alt"), text: "Alt.\n")
            let before = try store.mainHead()

            try store.remove(scene: a1.id)
            #expect(try store.manifest().chapter(a.id)?.scenes.map(\.id) == [a2.id])
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent(a1.path).path))
            #expect(try store.repository.entry(atPath: a1.path, inTree: try store.repository.commit(try store.mainHead()).tree) == nil)
            #expect(try store.repository.commit(try store.mainHead()).message == "Remove A1")
            #expect(try store.repository.commit(try store.mainHead()).parents == [before])
            #expect(throws: ProjectStoreError.unknownScene(a1.id)) { try store.sceneText(a1.id) }
            // The text is still one commit back, and the take's ref still stands.
            #expect(try store.repository.entry(atPath: a1.path, inTree: try store.repository.commit(before).tree) != nil)
            #expect(try store.repository.resolve(take.id) == take.head)

            try store.remove(chapter: b.id)
            #expect(try store.manifest().chapters.map(\.id) == [a.id])
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent(b1.path).path))
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent(b.folder).path))
            #expect(try store.repository.commit(try store.mainHead()).message == "Remove chapter B")

            try store.remove(part: part.id)
            #expect(try store.manifest().parts.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent(a2.path).path))
            #expect(try store.repository.commit(try store.mainHead()).message == "Remove part One")
            #expect(try git("status", "--porcelain", in: url) == "")
            #expect(try git("ls-files", in: url) == "manuscript.json\n")
        }
    }

    @Test func openRefusesAManifestOfAnotherFormat() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let manifest = try String(contentsOf: url.appendingPathComponent("manuscript.json"), encoding: .utf8)
            #expect(manifest.contains("\"format\" : 2"))

            let old = "{\"title\":\"P&P\",\"chapters\":[]}\n"
            try store.repository.writeWorkingFile(atPath: "manuscript.json", data: Data(old.utf8))
            let tree = try store.repository.writeIndexTree()
            try store.repository.createCommit(tree: tree, parents: [try store.mainHead()], author: jane, message: "Old", updatingRef: ProjectStore.mainRef)
            #expect(throws: ProjectStoreError.unsupportedFormat(1)) { try ProjectStore.open(at: url, author: jane) }
        }
    }

    @Test func checkpointSkipsUnchangedTextAndCommitsChangedText() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: opening)
            let before = try store.mainHead()

            #expect(try store.checkpoint(scene.id, text: opening) == nil)
            #expect(try store.checkpoint(scene.id, text: String(opening.dropLast())) == nil)
            #expect(try store.checkpoint(scene.id, text: opening + "\n\n") == nil)
            #expect(try store.mainHead() == before)

            let revised = opening.replacingOccurrences(of: "good fortune", with: "large fortune")
            let commit = try #require(try store.checkpoint(scene.id, text: revised))
            #expect(try store.mainHead() == commit)
            let info = try store.repository.commit(commit)
            #expect(info.parents == [before])
            #expect(info.message == "Checkpoint: Opening")
            #expect(try store.sceneText(scene.id) == revised)
            #expect(try store.sceneText(scene.id, at: before) == opening)
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data(revised.utf8))

            let named = try #require(try store.checkpoint(scene.id, text: revised + "\n\nA new paragraph.", message: "Add a paragraph"))
            #expect(try store.repository.commit(named).message == "Add a paragraph")
            #expect(try store.sceneText(scene.id) == revised + "\n\nA new paragraph.\n")
        }
    }

    @Test func milestoneIsATagAndMovesNothing() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "One.\n")
            let before = try store.mainHead()

            let first = try store.milestone(named: "First Draft!")
            #expect(first.id == "refs/tags/milestones/first-draft")
            #expect(first.name == "First Draft!")
            #expect(first.commit == before)
            #expect(abs(first.date.timeIntervalSinceNow) < 60)
            #expect(try store.mainHead() == before)
            #expect(try store.history(of: scene.id).count == 1)

            // A second milestone of the same name keeps its name and gets its own ref.
            try store.checkpoint(scene.id, text: "One. Two.\n")
            let second = try store.milestone(named: "first draft")
            #expect(second.id == "refs/tags/milestones/first-draft-2")
            #expect(second.commit == (try store.mainHead()))

            let listed = try store.milestones()
            #expect(listed.map(\.id) == [second.id, first.id])
            #expect(listed.map(\.name) == ["first draft", "First Draft!"])
            #expect(listed.map(\.commit) == [second.commit, first.commit])
            #expect(try store.sceneText(scene.id, at: first.commit) == "One.\n")
            #expect(try store.sceneText(scene.id, at: second.commit) == "One. Two.\n")

            // System git sees annotated tags with the name as the message.
            #expect(try git("tag", "-l", "-n1", "milestones/*", in: url) == "milestones/first-draft First Draft!\nmilestones/first-draft-2 first draft\n")
            #expect(try git("rev-parse", "milestones/first-draft^{commit}", in: url).trimmingCharacters(in: .whitespacesAndNewlines) == before.hex)
            #expect(try git("log", "--oneline", in: url).contains("Milestone") == false)
        }
    }

    @Test func historyListsOnlyCommitsThatChangedTheScene() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "One.\n")
            let added = try store.mainHead()
            let other = try store.addScene(title: "Other", toChapter: nil, text: "Elsewhere.\n")
            let first = try #require(try store.checkpoint(scene.id, text: "One. Two.\n"))
            try store.milestone(named: "Draft")
            try store.checkpoint(other.id, text: "Elsewhere, changed.\n")
            let second = try #require(try store.checkpoint(scene.id, text: "One. Two. Three.\n"))

            let take = try store.createTake(for: scene.id, name: "Bolder")
            let saved = try store.saveTake(take, text: "ONE. TWO. THREE.\n")
            guard case .kept(let merge) = try store.keep(saved) else { Issue.record("keep did not merge"); return }

            let history = try store.history(of: scene.id)
            #expect(history.map(\.id) == [merge, second, first, added])
            #expect(history.map(\.kind) == [.keep, .checkpoint, .checkpoint, .checkpoint])
            #expect(history.map(\.message) == ["Keep: Bolder - Opening", "Checkpoint: Opening", "Checkpoint: Opening", "Add Opening"])
            #expect(abs(history[0].date.timeIntervalSinceNow) < 60)
            #expect(try store.history(of: scene.id, limit: 2).map(\.id) == [merge, second])
            #expect(try store.history(of: other.id).map(\.message) == ["Checkpoint: Other", "Add Other"])
        }
    }

    @Test func historyReadAgainMatchesAFreshRead() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "One.\n")
            let other = try store.addScene(title: "Other", toChapter: nil, text: "Elsewhere.\n")
            // Read once, so every later read has something to continue from.
            #expect(try store.history(of: scene.id).count == 1)
            #expect(try store.history(of: scene.id, limit: 1).count == 1)

            for n in 2...6 {
                try store.checkpoint(scene.id, text: "One. \(n)\n")
                try store.checkpoint(other.id, text: "Elsewhere. \(n)\n")
                try store.rename(scene: other.id, to: "Other \(n)")
                let fresh = try ProjectStore.open(at: url, author: jane)
                // The short read first, so the full one after it must not trust it.
                #expect(try store.history(of: scene.id, limit: 2) == fresh.history(of: scene.id, limit: 2))
                #expect(try store.history(of: scene.id) == fresh.history(of: scene.id))
                #expect(try store.history(of: scene.id).count == n)
                #expect(try store.history(of: other.id) == fresh.history(of: other.id))
            }
            // A read cut short by its limit does not shorten a fuller read after it.
            #expect(try store.history(of: scene.id, limit: 3).count == 3)
            #expect(try store.history(of: scene.id, limit: 50).count == 6)
            let take = try store.saveTake(try store.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
            guard case .kept = try store.keep(take) else { Issue.record("keep did not merge"); return }
            let fresh = try ProjectStore.open(at: url, author: jane)
            #expect(try store.history(of: scene.id) == fresh.history(of: scene.id))
            #expect(try store.history(of: scene.id).first?.kind == .keep)
        }
    }

    @Test func manifestFollowsEveryCommit() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            #expect(try store.manifest().scenes.isEmpty)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "One.\n")
            #expect(try store.manifest().scenes.map(\.id) == [scene.id])
            var edited = try store.manifest()
            edited.title = "Pride and Prejudice"
            try store.saveManifest(edited, message: "Retitle")
            #expect(try store.manifest().title == "Pride and Prejudice")
            // A commit made behind the store's back is seen as well.
            let fresh = try ProjectStore.open(at: url, author: jane)
            try fresh.rename(scene: scene.id, to: "A Truth")
            #expect(try store.manifest().scene(scene.id)?.title == "A Truth")
        }
    }

    @Test func takesAreCreatedSavedAndReadBack() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: opening)
            let head = try store.mainHead()
            let uuid = scene.id.uuid.uuidString.lowercased()

            let take = try store.createTake(for: scene.id, name: "Darker Opening")
            #expect(take.id == "refs/takes/\(uuid)/Darker%20Opening")
            #expect(take.scene == scene.id)
            #expect(take.name == "Darker Opening")
            #expect(take.base == head)
            #expect(take.head == head)
            #expect(try store.repository.resolve(take.id) == head)
            #expect(try store.takeText(take) == opening)

            let duplicate = try store.createTake(for: scene.id, name: "darker opening")
            #expect(duplicate.id == "refs/takes/\(uuid)/darker%20opening%202")
            #expect(duplicate.name == "darker opening 2")

            #expect(try store.saveTake(take, text: opening) == take)
            let darker = "It is a truth universally denied.\n"
            let saved = try store.saveTake(take, text: darker)
            #expect(saved.head != take.head)
            #expect(saved.base == head)
            #expect(saved.id == take.id)
            #expect(try store.repository.commit(saved.head).parents == [head])
            #expect(try store.repository.resolve(take.id) == saved.head)
            #expect(try store.takeText(saved) == darker)
            #expect(try store.sceneText(scene.id) == opening)
            #expect(try store.mainHead() == head)
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data(opening.utf8))

            let listed = try store.takes(for: scene.id)
            #expect(listed.map(\.id) == [take.id, duplicate.id])
            #expect(listed.map(\.name) == ["Darker Opening", "darker opening 2"])
            #expect(listed.map(\.base) == [head, head])
            #expect(listed.map(\.head) == [saved.head, head])
            #expect(try store.takes(for: SceneID()).isEmpty)
        }
    }

    @Test func takeNamesSurviveTheRefAndItsRules() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            let uuid = scene.id.uuid.uuidString.lowercased()
            let names = ["Mr. Bennet's reply…", "..", "a/b:c?d*e[f\\g^h~i", "@{ref}", " Ends with dot.", "  ", "Ünïcode naïveté", "take.lock"]
            var made: [Take] = []
            for name in names { made.append(try store.createTake(for: scene.id, name: name)) }
            #expect(made.map(\.name) == ["Mr. Bennet's reply…", "..", "a/b:c?d*e[f\\g^h~i", "@{ref}", "Ends with dot.", "Take", "Ünïcode naïveté", "take.lock"])
            #expect(made[0].id == "refs/takes/\(uuid)/Mr%2E%20Bennet%27s%20reply%E2%80%A6")
            #expect(made[6].id == "refs/takes/\(uuid)/Ünïcode%20naïveté")
            #expect(Set(try store.takes(for: scene.id).map(\.name)) == Set(made.map(\.name)))
            // System git can list and read every one of them.
            #expect(try git("for-each-ref", "--count=100", "--format=%(refname)", "refs/takes/", in: url).split(separator: "\n").count == names.count)
            #expect(try git("rev-parse", "refs/takes/\(uuid)/Ünïcode%20naïveté", in: url).trimmingCharacters(in: .whitespacesAndNewlines) == made[6].head.hex)
            #expect(ProjectStore.refComponent("") == "Take")
            #expect(ProjectStore.takeName(fromRef: "refs/takes/x/Take%202", prefix: "refs/takes/x/") == "Take 2")
        }
    }

    @Test func keepFastForwardsMainOntoTheTake() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: opening)
            let other = try store.addScene(title: "Other", toChapter: nil, text: "Elsewhere.\n")

            let take = try store.createTake(for: scene.id, name: "Bolder")
            let bolder = "IT IS A TRUTH.\n"
            let saved = try store.saveTake(take, text: bolder)
            // Main moving on another scene is not a conflict for this one.
            let unrelated = try #require(try store.checkpoint(other.id, text: "Elsewhere, later.\n"))

            let result = try store.keep(saved)
            guard case .kept(let merge) = result else { Issue.record("expected .kept, got \(result)"); return }
            #expect(try store.mainHead() == merge)
            let info = try store.repository.commit(merge)
            #expect(info.parents == [unrelated, saved.head])
            #expect(info.message == "Keep: Bolder - Opening")
            #expect(try store.sceneText(scene.id) == bolder)
            #expect(try store.sceneText(other.id) == "Elsewhere, later.\n")
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data(bolder.utf8))
            #expect(try store.repository.resolve(take.id) == nil)
            #expect(try store.takes(for: scene.id).isEmpty)
            #expect(try store.repository.writeIndexTree() == info.tree)
        }
    }

    @Test func keepTouchesNoFileButTheScenes() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            let other = try store.addScene(title: "Other", toChapter: nil, text: "Elsewhere.\n")
            let take = try store.saveTake(try store.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")

            // Another tool has edited a scene on disk and left it uncommitted.
            let edited = Data("Elsewhere, edited by hand.\n".utf8)
            try edited.write(to: url.appendingPathComponent(other.path))

            guard case .kept = try store.keep(take) else { Issue.record("keep did not merge"); return }
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data("Alt.\n".utf8))
            #expect(try Data(contentsOf: url.appendingPathComponent(other.path)) == edited)
            #expect(try git("status", "--porcelain", in: url) == " M \(other.path)\n")

            // The same through a settled conflict, either way.
            let second = try store.saveTake(try store.createTake(for: scene.id, name: "Second"), text: "Second.\n")
            try store.checkpoint(scene.id, text: "Moved.\n")
            try store.keep(second, choosing: .take)
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data("Second.\n".utf8))
            #expect(try Data(contentsOf: url.appendingPathComponent(other.path)) == edited)
            let third = try store.saveTake(try store.createTake(for: scene.id, name: "Third"), text: "Third.\n")
            try store.checkpoint(scene.id, text: "Moved again.\n")
            try store.keep(third, choosing: .main)
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data("Moved again.\n".utf8))
            #expect(try Data(contentsOf: url.appendingPathComponent(other.path)) == edited)
        }
    }

    @Test func keepOfATakeWithNothingNewDropsTheRefWithoutAMerge() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            let other = try store.addScene(title: "Other", toChapter: nil, text: "Elsewhere.\n")

            // Nothing moved on either side: no commit, just the ref gone.
            let untouched = try store.createTake(for: scene.id, name: "Untouched")
            let head = try store.mainHead()
            #expect(try store.keep(untouched) == .kept(head))
            #expect(try store.mainHead() == head)
            #expect(try store.repository.resolve(untouched.id) == nil)

            // Main moved on another scene: still nothing of the take's to merge.
            let idle = try store.createTake(for: scene.id, name: "Idle")
            let moved = try #require(try store.checkpoint(other.id, text: "Elsewhere, later.\n"))
            #expect(try store.keep(idle) == .kept(moved))
            #expect(try store.mainHead() == moved)
            #expect(try store.repository.resolve(idle.id) == nil)
            #expect(try store.takes(for: scene.id).isEmpty)
            #expect(try git("log", "--merges", "--oneline", in: url) == "")
            #expect(try git("status", "--porcelain", in: url) == "")
            #expect(try store.history(of: scene.id).map(\.kind) == [.checkpoint])

            // Main moved on this scene: the take's text is the base, and that is still a conflict.
            let late = try store.createTake(for: scene.id, name: "Late")
            try store.checkpoint(scene.id, text: "Main.\n")
            #expect(try store.keep(late) == .conflict(base: "Base.\n", main: "Main.\n", take: "Base.\n"))
            #expect(try store.repository.resolve(late.id) == late.head)
        }
    }

    @Test func keepReportsAConflictWhenMainMovedAndWritesNothing() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            let take = try store.createTake(for: scene.id, name: "Alt")
            let saved = try store.saveTake(take, text: "Take.\n")
            let moved = try #require(try store.checkpoint(scene.id, text: "Main.\n"))

            let result = try store.keep(saved)
            #expect(result == .conflict(base: "Base.\n", main: "Main.\n", take: "Take.\n"))
            #expect(try store.mainHead() == moved)
            #expect(try store.sceneText(scene.id) == "Main.\n")
            #expect(try store.repository.resolve(take.id) == saved.head)
            #expect(try store.takes(for: scene.id).map(\.base) == [take.base])
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data("Main.\n".utf8))
        }
    }

    @Test func keepChoosingASideSettlesAConflictWholeScene() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")

            // The take wins: main carries its text, with the take as second parent.
            let alt = try store.saveTake(try store.createTake(for: scene.id, name: "Alt"), text: "Take.\n")
            let moved = try #require(try store.checkpoint(scene.id, text: "Main.\n"))
            #expect(try store.keep(alt) == .conflict(base: "Base.\n", main: "Main.\n", take: "Take.\n"))
            let kept = try store.keep(alt, choosing: .take)
            #expect(try store.mainHead() == kept)
            let info = try store.repository.commit(kept)
            #expect(info.parents == [moved, alt.head])
            #expect(info.message == "Keep: Alt - Opening")
            #expect(try store.sceneText(scene.id) == "Take.\n")
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data("Take.\n".utf8))
            #expect(try store.repository.resolve(alt.id) == nil)
            #expect(try store.history(of: scene.id).map(\.kind) == [.keep, .checkpoint, .checkpoint])

            // Main wins: the text stays, the take is still recorded and gone.
            let other = try store.saveTake(try store.createTake(for: scene.id, name: "Other"), text: "Other.\n")
            let later = try #require(try store.checkpoint(scene.id, text: "Main again.\n"))
            let settled = try store.keep(other, choosing: .main)
            let record = try store.repository.commit(settled)
            #expect(record.parents == [later, other.head])
            #expect(record.message == "Keep main over: Other - Opening")
            #expect(record.tree == (try store.repository.commit(later).tree))
            #expect(try store.sceneText(scene.id) == "Main again.\n")
            #expect(try store.repository.resolve(other.id) == nil)
            #expect(try store.takes(for: scene.id).isEmpty)
            #expect(try git("status", "--porcelain", in: url) == "")
            // The scene's own history skips the record, since its text did not move.
            #expect(try store.history(of: scene.id).first?.id == later)
        }
    }

    @Test func restoreBringsADiscardedTakeBack() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            let take = try store.saveTake(try store.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
            try store.discard(take)
            let discarded = try #require(try store.discardedTakes(for: scene.id).first)

            // Meanwhile the name was reused, so the restored take steps aside.
            let reused = try store.createTake(for: scene.id, name: "alt")
            let restored = try store.restore(discarded: discarded)
            #expect(restored.name == "Alt 2")
            #expect(restored.id == take.id.replacingOccurrences(of: "/Alt", with: "/Alt%202"))
            #expect(restored.head == take.head)
            #expect(restored.base == take.base)
            #expect(try store.takeText(restored) == "Alt.\n")
            #expect(try store.discardedTakes(for: scene.id).isEmpty)
            #expect(Set(try store.takes(for: scene.id).map(\.name)) == [reused.name, "Alt 2"])
        }
    }

    @Test func discardMovesTheRefAside() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "P&P", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            let uuid = scene.id.uuid.uuidString.lowercased()
            let take = try store.saveTake(try store.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")

            try store.discard(take)
            #expect(try store.repository.resolve(take.id) == nil)
            #expect(try store.takes(for: scene.id).isEmpty)
            #expect(try store.repository.resolve("refs/discarded/\(uuid)/Alt") == take.head)

            let second = try store.saveTake(try store.createTake(for: scene.id, name: "Alt"), text: "Alt again.\n")
            try store.discard(second)
            #expect(try store.repository.resolve("refs/discarded/\(uuid)/Alt") == take.head)
            #expect(try store.repository.resolve("refs/discarded/\(uuid)/Alt%202") == second.head)

            let discarded = try store.discardedTakes(for: scene.id)
            #expect(discarded.map(\.name) == ["Alt", "Alt 2"])
            #expect(discarded.map(\.head) == [take.head, second.head])
            #expect(discarded.map(\.base) == [take.base, second.base])
            #expect(try store.takeText(discarded[1]) == "Alt again.\n")
            #expect(try store.discardedTakes(for: SceneID()).isEmpty)
        }
    }

    @Test func systemGitReadsTheProject() throws {
        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "Pride and Prejudice", author: jane)
            let scene = try store.addScene(title: "Opening", toChapter: nil, text: opening)
            try store.checkpoint(scene.id, text: opening.replacingOccurrences(of: "good", with: "large"))
            try store.checkpoint(scene.id, text: opening.replacingOccurrences(of: "good", with: "vast"))
            let take = try store.createTake(for: scene.id, name: "Plainer")
            let saved = try store.saveTake(take, text: "A rich single man needs a wife.\n")
            guard case .kept(let merge) = try store.keep(saved) else { Issue.record("keep did not merge"); return }

            #expect(try git("rev-parse", "HEAD", in: url).trimmingCharacters(in: .whitespacesAndNewlines) == merge.hex)
            #expect(try git("symbolic-ref", "HEAD", in: url).trimmingCharacters(in: .whitespacesAndNewlines) == "refs/heads/main")
            #expect(try git("status", "--porcelain", in: url) == "")

            let graph = try git("log", "--oneline", "--graph", in: url)
            #expect(graph.hasPrefix("*   \(merge.short) Keep: Plainer - Opening\n|\\"), "\(graph)")
            #expect(graph.contains("Take: Plainer - Opening"))
            #expect(graph.contains("Checkpoint: Opening"))
            #expect(graph.contains("Begin Pride and Prejudice"))
            #expect(try git("log", "--format=%an <%ae>", "-1", in: url) == "Jane Austen <jane@example.com>\n")
            #expect(try git("show", "HEAD:\(scene.path)", in: url) == "A rich single man needs a wife.\n")
        }
    }
}
