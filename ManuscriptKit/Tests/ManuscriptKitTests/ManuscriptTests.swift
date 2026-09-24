import Foundation
import Testing
@testable import ManuscriptKit

/// The manifest on its own: shape changes that touch no repository.
@Suite struct ManuscriptTests {
    private static func fixture() -> (Manuscript, Part, Part, Chapter, Chapter, SceneRef, SceneRef, SceneRef) {
        let a1 = SceneRef(id: SceneID(), title: "A1", path: "chapters/01-a/01-a1.md")
        let a2 = SceneRef(id: SceneID(), title: "A2", path: "chapters/01-a/02-a2.md")
        let b1 = SceneRef(id: SceneID(), title: "B1", path: "chapters/02-b/01-b1.md")
        let a = Chapter(title: "A", folder: "chapters/01-a", scenes: [a1, a2])
        let b = Chapter(title: "B", folder: "chapters/02-b", scenes: [b1])
        let one = Part(title: "One", chapters: [a])
        let two = Part(title: "Two", chapters: [b])
        return (Manuscript(title: "P&P", parts: [one, two]), one, two, a, b, a1, a2, b1)
    }

    @Test func readsAcrossTheWholeTree() {
        let (m, one, two, a, b, a1, a2, b1) = Self.fixture()
        #expect(m.format == 2)
        #expect(m.chapters.map(\.id) == [a.id, b.id])
        #expect(m.scenes.map(\.id) == [a1.id, a2.id, b1.id])
        #expect(m.part(two.id)?.title == "Two")
        #expect(m.chapter(b.id)?.folder == "chapters/02-b")
        #expect(m.scene(a2.id)?.path == "chapters/01-a/02-a2.md")
        #expect(m.part(containing: b.id)?.id == two.id)
        #expect(m.chapter(containing: a2.id)?.id == a.id)
        #expect(m.part(containing: UUID()) == nil)
        #expect(m.chapter(containing: SceneID()) == nil)
        #expect(m.part(one.id)?.chapters.map(\.id) == [a.id])
    }

    @Test func roundTripsThroughJSON() throws {
        let (m, _, _, _, _, _, _, _) = Self.fixture()
        let data = try JSONEncoder().encode(m)
        #expect(try JSONDecoder().decode(Manuscript.self, from: data) == m)
        #expect(String(decoding: data, as: UTF8.self).contains("\"format\":2"))
    }

    @Test func movesCountTheIndexAfterRemoval() throws {
        var (m, one, two, a, b, a1, a2, b1) = Self.fixture()

        // Within a chapter: to the end, then back to the front.
        try m.move(scene: a1.id, toChapter: a.id, at: 1)
        #expect(m.chapter(a.id)?.scenes.map(\.id) == [a2.id, a1.id])
        try m.move(scene: a1.id, toChapter: a.id, at: 0)
        #expect(m.chapter(a.id)?.scenes.map(\.id) == [a1.id, a2.id])

        // Across chapters, with an index past the end.
        try m.move(scene: a1.id, toChapter: b.id, at: 7)
        #expect(m.chapter(a.id)?.scenes.map(\.id) == [a2.id])
        #expect(m.chapter(b.id)?.scenes.map(\.id) == [b1.id, a1.id])

        try m.move(chapter: b.id, toPart: one.id, at: 0)
        #expect(m.part(one.id)?.chapters.map(\.id) == [b.id, a.id])
        #expect(m.part(two.id)?.chapters.isEmpty == true)

        try m.move(part: two.id, to: 0)
        #expect(m.parts.map(\.id) == [two.id, one.id])
        try m.move(part: two.id, to: 5)
        #expect(m.parts.map(\.id) == [one.id, two.id])
    }

    @Test func renamesAndRemovals() throws {
        var (m, one, _, a, b, a1, a2, b1) = Self.fixture()
        try m.rename(part: one.id, to: "Volume One")
        try m.rename(chapter: a.id, to: "Alpha")
        try m.rename(scene: a1.id, to: "First")
        #expect(m.part(one.id)?.title == "Volume One")
        #expect(m.chapter(a.id)?.title == "Alpha")
        #expect(m.chapter(a.id)?.folder == "chapters/01-a")
        #expect(m.scene(a1.id)?.title == "First")
        #expect(m.scene(a1.id)?.path == a1.path)

        #expect(try m.remove(scene: a2.id).id == a2.id)
        #expect(m.scenes.map(\.id) == [a1.id, b1.id])
        #expect(try m.remove(chapter: b.id).scenes.map(\.id) == [b1.id])
        #expect(m.chapters.map(\.id) == [a.id])
        #expect(try m.remove(part: one.id).chapters.map(\.id) == [a.id])
        #expect(m.parts.map(\.title) == ["Two"])
        #expect(m.scenes.isEmpty)
    }

    @Test func aFailedMutationLeavesTheManuscriptAsItWas() throws {
        var (m, one, _, a, _, a1, _, _) = Self.fixture()
        let before = m
        let ghost = UUID()
        let ghostScene = SceneID()
        #expect(throws: ProjectStoreError.unknownPart(ghost)) { try m.rename(part: ghost, to: "X") }
        #expect(throws: ProjectStoreError.unknownChapter(ghost)) { try m.rename(chapter: ghost, to: "X") }
        #expect(throws: ProjectStoreError.unknownChapter(ghost)) { try m.move(scene: a1.id, toChapter: ghost, at: 0) }
        #expect(throws: ProjectStoreError.unknownScene(ghostScene)) { try m.move(scene: ghostScene, toChapter: a.id, at: 0) }
        #expect(throws: ProjectStoreError.unknownPart(ghost)) { try m.move(chapter: a.id, toPart: ghost, at: 0) }
        #expect(throws: ProjectStoreError.unknownChapter(ghost)) { try m.move(chapter: ghost, toPart: one.id, at: 0) }
        #expect(throws: ProjectStoreError.unknownPart(ghost)) { try m.move(part: ghost, to: 0) }
        #expect(throws: ProjectStoreError.unknownScene(ghostScene)) { try m.remove(scene: ghostScene) }
        #expect(throws: ProjectStoreError.unknownChapter(ghost)) { try m.remove(chapter: ghost) }
        #expect(throws: ProjectStoreError.unknownPart(ghost)) { try m.remove(part: ghost) }
        #expect(throws: ProjectStoreError.unknownChapter(ghost)) { try m.append(SceneRef(id: SceneID(), title: "X", path: "x.md"), toChapter: ghost) }
        #expect(throws: ProjectStoreError.unknownPart(ghost)) { try m.append(Chapter(title: "X", folder: "chapters/09-x"), toPart: ghost) }
        #expect(m == before)
    }
}
