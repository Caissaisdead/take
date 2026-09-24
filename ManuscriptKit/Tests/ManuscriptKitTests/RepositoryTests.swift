import Foundation
import Testing
@testable import ManuscriptKit

/// A fresh folder under the temporary directory, removed when `body` returns.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("manuscriptkit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

let jane = Signature(name: "Jane Austen", email: "jane@example.com")

private func data(_ text: String) -> Data { Data(text.utf8) }

@Suite struct RepositoryTests {
    @Test func createsAndOpens() throws {
        try withTemporaryDirectory { url in
            let created = try Repository.create(at: url)
            #expect(created.workingDirectory == url)
            #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent(".git/HEAD").path))
            let head = try String(contentsOf: url.appendingPathComponent(".git/HEAD"), encoding: .utf8)
            #expect(head == "ref: refs/heads/main\n")

            let opened = try Repository.open(at: url)
            #expect(opened.workingDirectory == url)
        }
    }

    @Test func openingAMissingFolderThrowsGitError() throws {
        try withTemporaryDirectory { url in
            #expect(throws: GitError.self) { try Repository.open(at: url) }
        }
    }

    @Test func unbornHeadResolvesNil() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            #expect(try repo.resolve("HEAD") == nil)
            #expect(try repo.resolve("refs/heads/main") == nil)
            #expect(try repo.resolve("refs/heads/nowhere") == nil)
        }
    }

    @Test func blobRoundTripsIncludingNonASCII() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let text = "Zoë met Mr Darcy at the café — “sans doute” ☕\n"
            let id = try repo.writeBlob(data(text))
            #expect(try repo.readBlob(id) == data(text))
            #expect(String(decoding: try repo.readBlob(id), as: UTF8.self) == text)

            // The id must be git's own hash, or no other tool can read the store.
            #expect(try repo.writeBlob(data("hello\n")).hex == "ce013625030ba8dba906f756967f9e9ca394464a")
            #expect(try repo.readBlob(try repo.writeBlob(Data())) == Data())
        }
    }

    @Test func treeReplaceRemoveAndUntouchedEntries() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let one = try repo.writeBlob(data("one\n"))
            let two = try repo.writeBlob(data("two\n"))
            let three = try repo.writeBlob(data("three\n"))

            var tree = try repo.tree(replacing: "chapters/01-a/01-b.md", with: one, in: nil)
            tree = try repo.tree(replacing: "chapters/01-a/02-c.md", with: two, in: tree)
            tree = try repo.tree(replacing: "manuscript.json", with: three, in: tree)

            let root = try repo.entries(ofTree: tree)
            #expect(root.map(\.name) == ["chapters", "manuscript.json"])
            #expect(root.map(\.kind) == [.tree, .blob])
            let chapters = try repo.entry(atPath: "chapters", inTree: tree)
            #expect(chapters?.kind == .tree)
            let folder = try repo.entry(atPath: "chapters/01-a", inTree: tree)
            #expect(try repo.entries(ofTree: try #require(folder).id).map(\.name) == ["01-b.md", "02-c.md"])
            #expect(try repo.entry(atPath: "chapters/01-a/01-b.md", inTree: tree)?.id == one)
            #expect(try repo.entry(atPath: "chapters/01-a/nope.md", inTree: tree) == nil)
            #expect(try repo.entry(atPath: "nope/nope.md", inTree: tree) == nil)

            // Replacing one leaf changes only the trees on its path.
            let replaced = try repo.tree(replacing: "chapters/01-a/01-b.md", with: three, in: tree)
            #expect(replaced != tree)
            #expect(try repo.entry(atPath: "chapters/01-a/01-b.md", inTree: replaced)?.id == three)
            #expect(try repo.entry(atPath: "chapters/01-a/02-c.md", inTree: replaced)?.id == two)
            let manifestBefore = try repo.entry(atPath: "manuscript.json", inTree: tree)
            #expect(try repo.entry(atPath: "manuscript.json", inTree: replaced) == manifestBefore)
            #expect(try repo.entry(atPath: "chapters", inTree: replaced)?.id != chapters?.id)

            // Removing.
            let removed = try repo.tree(replacing: "chapters/01-a/01-b.md", with: nil, in: replaced)
            #expect(try repo.entry(atPath: "chapters/01-a/01-b.md", inTree: removed) == nil)
            #expect(try repo.entry(atPath: "chapters/01-a/02-c.md", inTree: removed)?.id == two)
            #expect(try repo.tree(replacing: "chapters/01-a/never.md", with: nil, in: removed) == removed)
            #expect(try repo.tree(replacing: "elsewhere/never.md", with: nil, in: removed) == removed)

            // Emptying a folder drops the folder, as git itself would.
            let emptied = try repo.tree(replacing: "chapters/01-a/02-c.md", with: nil, in: removed)
            #expect(try repo.entries(ofTree: emptied).map(\.name) == ["manuscript.json"])
        }
    }

    @Test func commitRoundTripWithParentsAndMessage() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let blob = try repo.writeBlob(data("draft\n"))
            let tree = try repo.tree(replacing: "a.md", with: blob, in: nil)
            let when = Date(timeIntervalSince1970: 1_700_000_000)
            let author = Signature(name: "Jane Austen", email: "jane@example.com", time: when)

            let root = try repo.createCommit(tree: tree, parents: [], author: author, message: "Begin", updatingRef: "refs/heads/main")
            #expect(try repo.resolve("refs/heads/main") == root)
            #expect(try repo.resolve("HEAD") == root)

            let info = try repo.commit(root)
            #expect(info.id == root)
            #expect(info.parents.isEmpty)
            #expect(info.tree == tree)
            #expect(info.message == "Begin")
            #expect(info.author.name == "Jane Austen")
            #expect(info.author.email == "jane@example.com")
            #expect(info.author.time == when)

            let second = try repo.createCommit(tree: tree, parents: [root], author: author, message: "Second\n\nWith a body.", updatingRef: "refs/heads/main")
            #expect(try repo.commit(second).parents == [root])
            #expect(try repo.commit(second).message == "Second\n\nWith a body.")

            let side = try repo.createCommit(tree: tree, parents: [root], author: author, message: "Side", updatingRef: nil)
            let merge = try repo.createCommit(tree: tree, parents: [second, side], author: author, message: "Merge", updatingRef: "refs/heads/main")
            #expect(try repo.commit(merge).parents == [second, side])
            #expect(try repo.resolve("refs/heads/main") == merge)
        }
    }

    @Test func refsCreateUpdateDeleteAndList() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let tree = try repo.tree(replacing: "a.md", with: try repo.writeBlob(data("a\n")), in: nil)
            let first = try repo.createCommit(tree: tree, parents: [], author: jane, message: "1", updatingRef: nil)
            let second = try repo.createCommit(tree: tree, parents: [first], author: jane, message: "2", updatingRef: nil)

            try repo.updateRef("refs/takes/s1/zeta", to: first, message: "make")
            try repo.updateRef("refs/takes/s1/alpha", to: first, message: "make")
            try repo.updateRef("refs/takes/s2/beta", to: first, message: "make")
            try repo.updateRef("refs/heads/main", to: first, message: "make")
            #expect(try repo.resolve("refs/takes/s1/zeta") == first)

            try repo.updateRef("refs/takes/s1/zeta", to: second, message: "move")
            #expect(try repo.resolve("refs/takes/s1/zeta") == second)

            #expect(try repo.refs(withPrefix: "refs/takes/") == ["refs/takes/s1/alpha", "refs/takes/s1/zeta", "refs/takes/s2/beta"])
            #expect(try repo.refs(withPrefix: "refs/takes/s1/") == ["refs/takes/s1/alpha", "refs/takes/s1/zeta"])
            #expect(try repo.refs(withPrefix: "refs/takes/s3/") == [])
            #expect(try repo.refs(withPrefix: "refs/heads/") == ["refs/heads/main"])

            try repo.deleteRef("refs/takes/s1/zeta")
            #expect(try repo.resolve("refs/takes/s1/zeta") == nil)
            #expect(try repo.refs(withPrefix: "refs/takes/s1/") == ["refs/takes/s1/alpha"])
            // libgit2 treats deleting a missing ref as already done.
            try repo.deleteRef("refs/takes/s1/zeta")
            #expect(try repo.refs(withPrefix: "refs/takes/s1/") == ["refs/takes/s1/alpha"])

            try repo.renameRef("refs/takes/s1/alpha", to: "refs/discarded/s1/alpha")
            #expect(try repo.resolve("refs/takes/s1/alpha") == nil)
            #expect(try repo.resolve("refs/discarded/s1/alpha") == first)
        }
    }

    @Test func setHeadPointsAtBranchWithoutTouchingFiles() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            try repo.writeWorkingFile(atPath: "a.md", data: data("a\n"))
            let commit = try repo.createCommit(tree: try repo.writeIndexTree(), parents: [], author: jane, message: "1", updatingRef: "refs/heads/other")
            try repo.setHead(toBranch: "other")
            #expect(try repo.resolve("HEAD") == commit)
            #expect(try String(contentsOf: url.appendingPathComponent(".git/HEAD"), encoding: .utf8) == "ref: refs/heads/other\n")
            try repo.setHead(toBranch: "main")
            #expect(try repo.resolve("HEAD") == nil)
            #expect(try Data(contentsOf: url.appendingPathComponent("a.md")) == data("a\n"))
        }
    }

    @Test func logIsNewestFirstAndHonoursLimit() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let tree = try repo.tree(replacing: "a.md", with: try repo.writeBlob(data("a\n")), in: nil)
            // Same second for all three: order must come from ancestry, not luck.
            let author = Signature(name: "J", email: "j@example.com", time: Date(timeIntervalSince1970: 1_700_000_000))
            let c1 = try repo.createCommit(tree: tree, parents: [], author: author, message: "1", updatingRef: "refs/heads/main")
            let c2 = try repo.createCommit(tree: tree, parents: [c1], author: author, message: "2", updatingRef: "refs/heads/main")
            let c3 = try repo.createCommit(tree: tree, parents: [c2], author: author, message: "3", updatingRef: "refs/heads/main")

            #expect(try repo.log(from: c3, limit: 10).map(\.id) == [c3, c2, c1])
            #expect(try repo.log(from: c3, limit: 2).map(\.id) == [c3, c2])
            #expect(try repo.log(from: c2, limit: 10).map(\.id) == [c2, c1])
            #expect(try repo.log(from: c3, limit: 0).isEmpty)

            // Distinct times: newest first across a merge as well.
            let later = Signature(name: "J", email: "j@example.com", time: Date(timeIntervalSince1970: 1_700_000_100))
            let side = try repo.createCommit(tree: tree, parents: [c1], author: later, message: "side", updatingRef: nil)
            let merge = try repo.createCommit(tree: tree, parents: [c3, side], author: later, message: "merge", updatingRef: "refs/heads/main")
            #expect(try repo.log(from: merge, limit: 10).map(\.id) == [merge, side, c3, c2, c1])
        }
    }

    @Test func mergeBaseFindsTheFork() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let tree = try repo.tree(replacing: "a.md", with: try repo.writeBlob(data("a\n")), in: nil)
            let c1 = try repo.createCommit(tree: tree, parents: [], author: jane, message: "1", updatingRef: nil)
            let c2 = try repo.createCommit(tree: tree, parents: [c1], author: jane, message: "2", updatingRef: nil)
            let c3 = try repo.createCommit(tree: tree, parents: [c1], author: jane, message: "3", updatingRef: nil)
            let c4 = try repo.createCommit(tree: tree, parents: [c3], author: jane, message: "4", updatingRef: nil)
            let other = try repo.createCommit(tree: tree, parents: [], author: jane, message: "other", updatingRef: nil)

            #expect(try repo.mergeBase(c2, c4) == c1)
            #expect(try repo.mergeBase(c4, c2) == c1)
            #expect(try repo.mergeBase(c1, c4) == c1)
            #expect(try repo.mergeBase(c2, c2) == c2)
            #expect(try repo.mergeBase(c2, other) == nil)
        }
    }

    @Test func indexTreeMatchesTreeBuiltByHand() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let manifest = data("{}\n")
            let scene = data("It is a truth universally acknowledged.\n")
            try repo.writeWorkingFile(atPath: "manuscript.json", data: manifest)
            try repo.writeWorkingFile(atPath: "chapters/01-longbourn/01-a-truth.md", data: scene)
            #expect(try Data(contentsOf: url.appendingPathComponent("chapters/01-longbourn/01-a-truth.md")) == scene)

            var byHand = try repo.tree(replacing: "manuscript.json", with: try repo.writeBlob(manifest), in: nil)
            byHand = try repo.tree(replacing: "chapters/01-longbourn/01-a-truth.md", with: try repo.writeBlob(scene), in: byHand)
            #expect(try repo.writeIndexTree() == byHand)

            try repo.removeWorkingFile(atPath: "chapters/01-longbourn/01-a-truth.md")
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("chapters/01-longbourn/01-a-truth.md").path))
            #expect(try repo.writeIndexTree() == repo.tree(replacing: "manuscript.json", with: try repo.writeBlob(manifest), in: nil))
        }
    }

    @Test func mergeFileMergesDifferentLinesAndConflictsOnTheSame() throws {
        try withTemporaryDirectory { url in
            let repo = try Repository.create(at: url)
            let ancestor = data("First paragraph.\nSecond paragraph.\nThird paragraph.\n")

            let apart = try repo.mergeFile(
                ancestor: ancestor,
                ours: data("First paragraph, revised.\nSecond paragraph.\nThird paragraph.\n"),
                theirs: data("First paragraph.\nSecond paragraph.\nThird paragraph, revised.\n"))
            #expect(apart.isAutomergeable)
            #expect(apart.content == data("First paragraph, revised.\nSecond paragraph.\nThird paragraph, revised.\n"))

            let together = try repo.mergeFile(
                ancestor: ancestor,
                ours: data("First paragraph, ours.\nSecond paragraph.\nThird paragraph.\n"),
                theirs: data("First paragraph, theirs.\nSecond paragraph.\nThird paragraph.\n"))
            #expect(!together.isAutomergeable)
            let text = String(decoding: together.content, as: UTF8.self)
            #expect(text.contains("<<<<<<<"))
            #expect(text.contains("First paragraph, ours.\n=======\nFirst paragraph, theirs.\n>>>>>>>"))

            let added = try repo.mergeFile(ancestor: Data(), ours: Data(), theirs: data("New.\n"))
            #expect(added.isAutomergeable)
            #expect(added.content == data("New.\n"))
        }
    }
}
