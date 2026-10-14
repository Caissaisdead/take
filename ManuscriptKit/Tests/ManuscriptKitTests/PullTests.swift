import Foundation
import Testing
@testable import ManuscriptKit

private let other = Signature(name: "Other Device", email: "other@example.com")

/// A bare repository under `url` and the file URL that reaches it.
private func makeRemote(in url: URL) throws -> String {
    let bare = try Repository.create(at: url.appendingPathComponent("remote.git"), bare: true)
    return "file://" + bare.workingDirectory.path
}

/// A project pushed to a fresh remote and a clone of it: the Mac and the
/// phone, with the phone's clock fixed so its take names can be checked.
private func twoSides(in url: URL, setUp: (ProjectStore) throws -> Void = { _ in }) throws -> (remote: String, a: ProjectStore, b: ProjectStore) {
    let remote = try makeRemote(in: url)
    let a = try ProjectStore.create(at: url.appendingPathComponent("a"), title: "P&P", author: jane)
    try setUp(a)
    try ProjectStore.backUp(projectAt: a.repository.workingDirectory, to: remote, token: nil)
    let b = try ProjectStore.clone(from: remote, to: url.appendingPathComponent("b"), token: nil, author: other)
    b.clock = { Date(timeIntervalSince1970: 1_792_000_000) }
    return (remote, a, b)
}

private func backUp(_ store: ProjectStore, to remote: String) throws {
    try ProjectStore.backUp(projectAt: store.repository.workingDirectory, to: remote, token: nil)
}

private func pull(_ store: ProjectStore, from remote: String) throws -> PullResult {
    let result = try ProjectStore.pull(projectAt: store.repository.workingDirectory, from: remote, token: nil)
    try store.reload()
    return result
}

private func fileText(_ store: ProjectStore, _ scene: SceneRef) throws -> String {
    String(decoding: try Data(contentsOf: store.repository.workingDirectory.appendingPathComponent(scene.path)), as: UTF8.self)
}

@Suite struct PullTests {
    @Test func cloneBringsMainTakesMilestonesAndDiscarded() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (_, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n", synopsis: "It begins", notes: "n")
                try a.milestone(named: "First draft")
                let alt = try a.saveTake(try a.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
                try a.discard(try a.saveTake(try a.createTake(for: scene.id, name: "Gone"), text: "Gone.\n"))
                _ = alt
            }
            #expect(try b.manifest() == (try a.manifest()))
            #expect(try b.mainHead() == (try a.mainHead()))
            #expect(try b.repository.resolve("HEAD") == (try a.mainHead()))
            #expect(try fileText(b, scene) == "Base.\n")
            #expect(try b.takes(for: scene.id) == (try a.takes(for: scene.id)))
            #expect(try b.discardedTakes(for: scene.id) == (try a.discardedTakes(for: scene.id)))
            #expect(try b.milestones() == (try a.milestones()))
            #expect(try b.takeText(try b.takes(for: scene.id)[0]) == "Alt.\n")
            #expect(try b.repository.refs(withPrefix: ProjectStore.stagingPrefix) == [])
        }
    }

    @Test func cloneRefusesARemoteWithoutAManifest() throws {
        try withTemporaryDirectory { url in
            let remote = try makeRemote(in: url)
            let plain = try Repository.create(at: url.appendingPathComponent("plain"))
            try plain.writeWorkingFile(atPath: "readme.md", data: Data("hi\n".utf8))
            _ = try plain.createCommit(tree: try plain.writeIndexTree(), parents: [], author: jane, message: "1", updatingRef: "refs/heads/main")
            try plain.push(to: remote, refspecs: ["refs/heads/main:refs/heads/main"], token: nil)
            #expect(throws: ProjectStoreError.missingFile(Manuscript.manifestPath)) {
                try ProjectStore.clone(from: remote, to: url.appendingPathComponent("b"), token: nil, author: other)
            }
        }
    }

    @Test func pullIsUpToDateWhenNothingMoved() throws {
        try withTemporaryDirectory { url in
            let (remote, _, b) = try twoSides(in: url) { a in
                _ = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            }
            let result = try pull(b, from: remote)
            #expect(result == PullResult(main: .alreadyUpToDate, brought: [], renamed: []))
        }
    }

    @Test func pullFastForwardsWhenOnlyTheRemoteMoved() throws {
        try withTemporaryDirectory { url in
            var opening: SceneRef!
            var doomed: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                opening = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
                doomed = try a.addScene(title: "Doomed", toChapter: nil, text: "Soon gone.\n")
            }
            try a.checkpoint(opening.id, text: "Once.\n")
            try a.checkpoint(opening.id, text: "Twice.\n")
            let fresh = try a.addScene(title: "Fresh", toChapter: nil, text: "New.\n")
            try a.remove(scene: doomed.id)
            try backUp(a, to: remote)

            let result = try pull(b, from: remote)
            #expect(result.main == .fastForwarded(commits: 4))
            #expect(result.brought.isEmpty)
            #expect(try b.mainHead() == (try a.mainHead()))
            #expect(try b.manifest() == (try a.manifest()))
            #expect(try fileText(b, opening) == "Twice.\n")
            #expect(try fileText(b, fresh) == "New.\n")
            #expect(!FileManager.default.fileExists(atPath: b.repository.workingDirectory.appendingPathComponent(doomed.path).path))
            // The index followed, so the next save commits only its own change.
            #expect(try b.repository.writeIndexTree() == (try b.repository.commit(try b.mainHead()).tree))
            #expect(try b.history(of: opening.id).map(\.message) == ["Checkpoint: Opening", "Checkpoint: Opening", "Add Opening"])
        }
    }

    @Test func pullReportsAheadWhenOnlyThisSideMoved() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (remote, _, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            }
            try b.checkpoint(scene.id, text: "Mine.\n")
            let head = try b.mainHead()
            #expect(try pull(b, from: remote).main == .ahead(commits: 1))
            #expect(try b.mainHead() == head)
            #expect(try fileText(b, scene) == "Mine.\n")
        }
    }

    @Test func pullFromAnEmptyRemoteSaysSo() throws {
        try withTemporaryDirectory { url in
            let remote = try makeRemote(in: url)
            let store = try ProjectStore.create(at: url.appendingPathComponent("a"), title: "P&P", author: jane)
            #expect(try pull(store, from: remote) == PullResult(main: .remoteEmpty, brought: [], renamed: []))
        }
    }

    @Test func pullBringsNewTakesAndMilestonesWithoutMovingMain() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            }
            let take = try a.saveTake(try a.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
            let milestone = try a.milestone(named: "First")
            try backUp(a, to: remote)

            let result = try pull(b, from: remote)
            #expect(result.main == .alreadyUpToDate)
            #expect(Set(result.brought) == [take.id, milestone.id])
            #expect(result.renamed.isEmpty)
            #expect(try b.takes(for: scene.id) == [take])
            #expect(try b.milestones() == [milestone])
            #expect(try b.repository.refs(withPrefix: ProjectStore.stagingPrefix) == [])
        }
    }

    @Test func pullMovesATakeSavedFurtherElsewhere() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            var take: Take!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
                take = try a.saveTake(try a.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
            }
            let further = try a.saveTake(take, text: "Alt, again.\n")
            try backUp(a, to: remote)
            let result = try pull(b, from: remote)
            #expect(result.brought == [take.id])
            #expect(try b.takes(for: scene.id) == [further])
            #expect(try b.takeText(further) == "Alt, again.\n")
        }
    }

    @Test func pullLeavesThisSidesNewerTakeAlone() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            var take: Take!
            let (remote, _, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
                take = try a.saveTake(try a.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
            }
            let mine = try b.saveTake(take, text: "Alt, mine.\n")
            let result = try pull(b, from: remote)
            #expect(result == PullResult(main: .alreadyUpToDate, brought: [], renamed: []))
            #expect(try b.takes(for: scene.id) == [mine])
        }
    }

    @Test func pullNumbersATakeBothSidesSaved() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            var take: Take!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
                take = try a.saveTake(try a.createTake(for: scene.id, name: "Alt"), text: "Alt.\n")
            }
            let theirs = try a.saveTake(take, text: "Alt, theirs.\n")
            try backUp(a, to: remote)
            let mine = try b.saveTake(take, text: "Alt, mine.\n")

            let result = try pull(b, from: remote)
            let numbered = take.id + "%202"
            #expect(result.renamed == [PullResult.Clash(remote: take.id, local: numbered)])
            #expect(result.brought == [numbered])
            let takes = try b.takes(for: scene.id)
            #expect(takes.map(\.name) == ["Alt", "Alt 2"])
            #expect(takes.map(\.head) == [mine.head, theirs.head])
            #expect(try b.takeText(takes[1]) == "Alt, theirs.\n")
        }
    }

    @Test func pullNumbersAMilestoneMadeTwice() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "Opening", toChapter: nil, text: "Base.\n")
            }
            try a.checkpoint(scene.id, text: "A's.\n")
            let theirs = try a.milestone(named: "First draft")
            try backUp(a, to: remote)
            let mine = try b.milestone(named: "First draft")

            let result = try pull(b, from: remote)
            #expect(result.renamed == [PullResult.Clash(remote: theirs.id, local: theirs.id + "-2")])
            #expect(Set(try b.milestones().map(\.id)) == [mine.id, theirs.id + "-2"])
            #expect(try b.milestones().map(\.name) == ["First draft", "First draft"])
        }
    }

    @Test func pullReportsDivergenceWithoutTouchingMain() throws {
        try withTemporaryDirectory { url in
            var s1: SceneRef!
            var s2: SceneRef!
            var s4: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                s1 = try a.addScene(title: "One", toChapter: nil, text: "One.\n")
                s2 = try a.addScene(title: "Two", toChapter: nil, text: "Two.\n")
                s4 = try a.addScene(title: "Four", toChapter: nil, text: "Four.\n")
            }
            try a.checkpoint(s1.id, text: "One, theirs.\n")
            try a.remove(scene: s4.id)
            try backUp(a, to: remote)
            try b.checkpoint(s1.id, text: "One, mine.\n")
            try b.checkpoint(s2.id, text: "Two, mine.\n")
            let s3 = try b.addScene(title: "Three", toChapter: nil, text: "Three.\n")
            let head = try b.mainHead()

            let result = try pull(b, from: remote)
            guard case .diverged(let divergence) = result.main else { Issue.record("not diverged: \(result)"); return }
            #expect(divergence.localMain == head)
            #expect(divergence.remoteMain == (try a.mainHead()))
            #expect(divergence.base != nil)
            #expect(divergence.changed.map(\.id) == [s1.id, s2.id])
            // The remote removed Four and this side left it alone: it goes.
            #expect(divergence.added.map(\.id) == [s3.id])
            #expect(try b.mainHead() == head)
            #expect(try fileText(b, s1) == "One, mine.\n")
            #expect(try b.repository.resolve(ProjectStore.remoteMainRef) == (try a.mainHead()))
        }
    }

    @Test func keepMineAsTakesMakesATakePerChangedSceneAndResetsMain() throws {
        try withTemporaryDirectory { url in
            var s1: SceneRef!
            var s2: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                s1 = try a.addScene(title: "One", toChapter: nil, text: "One.\n")
                s2 = try a.addScene(title: "Two", toChapter: nil, text: "Two.\n")
            }
            try a.checkpoint(s1.id, text: "One, theirs.\n")
            try backUp(a, to: remote)
            try b.checkpoint(s1.id, text: "One, mine.\n")
            try b.checkpoint(s2.id, text: "Two, mine.\n")
            let s3 = try b.addScene(title: "Three", toChapter: nil, text: "Three.\n")

            guard case .diverged(let divergence) = try pull(b, from: remote).main else { Issue.record("not diverged"); return }
            let takes = try b.keepMineAsTakes(divergence, device: "iPhone")

            // Main is the remote's plus one commit bringing Three back.
            let remoteMain = try a.mainHead()
            let head = try b.mainHead()
            #expect(try b.repository.commit(head).parents == [remoteMain])
            #expect(try b.repository.commit(head).message == "Bring Three from iPhone")
            #expect(try b.manifest().scenes.map(\.title) == ["One", "Two", "Three"])
            #expect(try b.sceneText(s1.id) == "One, theirs.\n")
            #expect(try fileText(b, s1) == "One, theirs.\n")
            #expect(try b.sceneText(s3.id) == "Three.\n")

            // One take per changed scene, holding this side's text.
            let name = "iPhone " + ProjectStore.pullName.string(from: Date(timeIntervalSince1970: 1_792_000_000))
            #expect(takes.map(\.name) == [name, name])
            #expect(takes.map(\.scene) == [s1.id, s2.id])
            #expect(try b.takeText(takes[0]) == "One, mine.\n")
            #expect(try b.takeText(takes[1]) == "Two, mine.\n")
            #expect(takes.map(\.base) == [head, head])

            // Each take is begun from the new main, so Keep puts its text back in one step.
            guard case .kept = try b.keep(takes[1]) else { Issue.record("Two did not keep"); return }
            #expect(try b.sceneText(s2.id) == "Two, mine.\n")
            guard case .kept = try b.keep(takes[0]) else { Issue.record("One did not keep"); return }
            #expect(try b.sceneText(s1.id) == "One, mine.\n")
            #expect(try b.takes(for: s1.id).isEmpty)
            // And the next save commits only its own change.
            #expect(try b.repository.writeIndexTree() == (try b.repository.commit(try b.mainHead()).tree))
        }
    }

    @Test func keepMineAsTakesRefusesAStaleDivergence() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "One", toChapter: nil, text: "One.\n")
            }
            try a.checkpoint(scene.id, text: "Theirs.\n")
            try backUp(a, to: remote)
            try b.checkpoint(scene.id, text: "Mine.\n")
            guard case .diverged(let divergence) = try pull(b, from: remote).main else { Issue.record("not diverged"); return }
            try b.checkpoint(scene.id, text: "Mine, more.\n")
            #expect(throws: ProjectStoreError.pullStale) { try b.keepMineAsTakes(divergence, device: "iPhone") }
            #expect(try b.sceneText(scene.id) == "Mine, more.\n")
        }
    }

    @Test func keepMineAsTakesNumbersASecondPullTheSameMinute() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "One", toChapter: nil, text: "One.\n")
            }
            let name = "iPhone " + ProjectStore.pullName.string(from: Date(timeIntervalSince1970: 1_792_000_000))
            for round in 1...2 {
                try a.checkpoint(scene.id, text: "Theirs \(round).\n")
                try backUp(a, to: remote)
                try b.checkpoint(scene.id, text: "Mine \(round).\n")
                guard case .diverged(let divergence) = try pull(b, from: remote).main else { Issue.record("not diverged"); return }
                try b.keepMineAsTakes(divergence, device: "iPhone")
            }
            #expect(try b.takes(for: scene.id).map(\.name) == [name, name + " 2"])
        }
    }

    @Test func backupAfterKeepMineAsTakesIsAccepted() throws {
        try withTemporaryDirectory { url in
            var scene: SceneRef!
            let (remote, a, b) = try twoSides(in: url) { a in
                scene = try a.addScene(title: "One", toChapter: nil, text: "One.\n")
            }
            try a.checkpoint(scene.id, text: "Theirs.\n")
            try backUp(a, to: remote)
            try b.checkpoint(scene.id, text: "Mine.\n")
            guard case .diverged(let divergence) = try pull(b, from: remote).main else { Issue.record("not diverged"); return }
            let takes = try b.keepMineAsTakes(divergence, device: "iPhone")
            try backUp(b, to: remote)

            // The Mac's next pull brings the phone's take and moves nothing else.
            let result = try pull(a, from: remote)
            #expect(result == PullResult(main: .alreadyUpToDate, brought: takes.map(\.id), renamed: []))
            #expect(try a.takes(for: scene.id) == takes)
            #expect(try a.takeText(takes[0]) == "Mine.\n")
        }
    }
}
