import Foundation
import Testing
@testable import ManuscriptKit

/// The loop the spike promises, run over the real sample scene: add, checkpoint,
/// take, diff, keep, and a second take that meets a main that moved.
@Suite struct EndToEndTests {
    static let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Take/Resources/sample-scene.md")

    /// `text` with one paragraph rewritten, back in stored form.
    private static func replacing(_ index: Int, in text: String, _ edit: (String) -> String) -> String {
        var paragraphs = Prose.paragraphs(text)
        paragraphs[index] = edit(paragraphs[index])
        return Prose.join(paragraphs)
    }

    @Test func addCheckpointTakeDiffKeepThenConflict() throws {
        let sample = try String(contentsOf: Self.sampleURL, encoding: .utf8)
        #expect(Prose.paragraphs(sample).count == 122)
        #expect(Prose.normalize(sample) == sample)

        try withTemporaryDirectory { url in
            let store = try ProjectStore.create(at: url, title: "Pride and Prejudice", author: jane)
            let scene = try store.addScene(title: "A Truth Universally Acknowledged", toChapter: nil, text: sample)
            #expect(try store.sceneText(scene.id) == sample)
            #expect(try store.history(of: scene.id).map(\.kind) == [.checkpoint])

            // A checkpoint on main: the opening line loses its comma.
            let checkpointed = Self.replacing(0, in: sample) {
                $0.replacingOccurrences(of: "acknowledged, that", with: "acknowledged that")
            }
            #expect(checkpointed != sample)
            let checkpoint = try #require(try store.checkpoint(scene.id, text: checkpointed))
            #expect(try store.sceneText(scene.id) == checkpointed)
            #expect(try store.checkpoint(scene.id, text: checkpointed) == nil)
            #expect(try store.history(of: scene.id).map(\.id) == [checkpoint, try store.repository.commit(checkpoint).parents[0]])

            // Two saves on a take, each touching one paragraph.
            let take = try store.createTake(for: scene.id, name: "Take 2")
            #expect(take.base == checkpoint)
            let answer = "Mr. Bennet made no answer at all."
            let firstEdit = Self.replacing(5, in: checkpointed) { _ in answer }
            let first = try store.saveTake(take, text: firstEdit)
            let secondEdit = Self.replacing(24, in: firstEdit) { "\($0) Not for a moment." }
            let second = try store.saveTake(first, text: secondEdit)
            #expect(second.id == take.id)
            #expect(try store.repository.commit(second.head).parents == [first.head])
            #expect(try store.repository.commit(first.head).parents == [checkpoint])
            #expect(try store.takeText(second) == secondEdit)
            #expect(try store.sceneText(scene.id) == checkpointed)
            #expect(try store.mainHead() == checkpoint)

            // Main against the take: exactly the two paragraphs, edited in place.
            let mainParagraphs = Prose.paragraphs(try store.sceneText(scene.id))
            let takeParagraphs = Prose.paragraphs(try store.takeText(second))
            #expect(mainParagraphs.count == takeParagraphs.count)
            let expected: [ProseDiff.Segment] = mainParagraphs.indices.map { index in
                let old = mainParagraphs[index], new = takeParagraphs[index]
                return old == new
                    ? .equal(old)
                    : .changed(old: old, new: new, words: ProseDiffer.wordDiff(old: old, new: new))
            }
            let diff = ProseDiffer.diff(old: try store.sceneText(scene.id), new: try store.takeText(second))
            #expect(diff.segments == expected)
            #expect(diff.summary.paragraphsChanged == 2)
            #expect(diff.summary.wordsAdded > 0)
            let changedAt = diff.segments.indices.filter { if case .changed = diff.segments[$0] { return true } else { return false } }
            #expect(changedAt == [5, 24])
            if case .changed(let old, let new, _) = diff.segments[5] {
                #expect(old == "Mr. Bennet made no answer.")
                #expect(new == answer)
            }

            // Keep: main carries the take's text and the take is gone.
            let result = try store.keep(second)
            guard case .kept(let merge) = result else { Issue.record("expected .kept, got \(result)"); return }
            #expect(try store.mainHead() == merge)
            #expect(try store.repository.commit(merge).parents == [checkpoint, second.head])
            #expect(try store.sceneText(scene.id) == secondEdit)
            #expect(try store.sceneText(scene.id) == (try store.takeText(second)))
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data(secondEdit.utf8))
            #expect(try store.takes(for: scene.id).isEmpty)
            let history = try store.history(of: scene.id)
            #expect(history.map(\.kind) == [.keep, .checkpoint, .checkpoint])
            #expect(history.map(\.id) == [merge, checkpoint, try store.repository.commit(checkpoint).parents[0]])
            #expect(history[0].message == "Keep: Take 2 - A Truth Universally Acknowledged")
            #expect(!ProseDiffer.diff(old: try store.sceneText(scene.id), new: secondEdit).hasChanges)

            // A second take, then main moves on the same scene: keep must refuse.
            let third = try store.createTake(for: scene.id, name: "Take 3")
            #expect(third.base == merge)
            let takeThree = Self.replacing(40, in: secondEdit) { "\($0) He went the very next morning." }
            let savedThird = try store.saveTake(third, text: takeThree)
            let moved = Self.replacing(11, in: secondEdit) { $0.replacingOccurrences(of: "large fortune", with: "vast fortune") }
            #expect(moved != secondEdit)
            let movedCommit = try #require(try store.checkpoint(scene.id, text: moved))

            let conflict = try store.keep(savedThird)
            #expect(conflict == .conflict(base: secondEdit, main: moved, take: takeThree))
            #expect(try store.mainHead() == movedCommit)
            #expect(try store.sceneText(scene.id) == moved)
            #expect(try store.repository.resolve(third.id) == savedThird.head)
            #expect(try store.takes(for: scene.id).map(\.head) == [savedThird.head])
            #expect(try Data(contentsOf: url.appendingPathComponent(scene.path)) == Data(moved.utf8))
            #expect(try store.history(of: scene.id).map(\.kind) == [.checkpoint, .keep, .checkpoint, .checkpoint])
        }
    }
}
