import Foundation

/// One hit of a search: where it is and the paragraph it sits in.
public struct Match: Hashable, Sendable, Identifiable {
    public var scene: SceneID
    /// The take the hit is in, or nil for main.
    public var take: Take?
    /// The paragraph's index in the stored text.
    public var paragraph: Int
    /// The hit within the paragraph, in UTF-16 units, as a text view counts.
    public var location: Int
    public var length: Int
    /// The whole paragraph.
    public var text: String

    public var id: String { "\(take?.id ?? "main"):\(scene.uuid.uuidString):\(paragraph):\(location)" }

    public init(scene: SceneID, take: Take?, paragraph: Int, location: Int, length: Int, text: String) {
        self.scene = scene
        self.take = take
        self.paragraph = paragraph
        self.location = location
        self.length = length
        self.text = text
    }
}

/// Finding a phrase in prose: case and accents do not matter, every
/// occurrence counts, and a hit never straddles a paragraph.
public enum ManuscriptSearch {
    public struct Hit: Hashable, Sendable {
        public var paragraph: Int
        public var location: Int
        public var length: Int
    }

    public static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Every hit of `needle` in `text`, in order. An empty or blank needle
    /// finds nothing.
    public static func hits(of needle: String, in text: String) -> [Hit] {
        let needle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [Hit] = []
        for (index, paragraph) in Prose.paragraphs(text).enumerated() {
            var from = paragraph.startIndex
            while from < paragraph.endIndex,
                  let range = paragraph.range(of: needle, options: options, range: from..<paragraph.endIndex) {
                let location = paragraph.utf16.distance(from: paragraph.startIndex, to: range.lowerBound)
                let length = paragraph.utf16.distance(from: range.lowerBound, to: range.upperBound)
                hits.append(Hit(paragraph: index, location: location, length: length))
                from = range.upperBound > from ? range.upperBound : paragraph.index(after: from)
            }
        }
        return hits
    }
}

extension ProjectStore {
    /// Every hit of `query` on main, in manuscript order, and in each scene's
    /// live takes after its main hits when asked.
    public func search(_ query: String, includingTakes: Bool) throws -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var matches: [Match] = []
        for scene in try manifest().scenes {
            let text = try sceneText(scene.id)
            let paragraphs = Prose.paragraphs(text)
            for hit in ManuscriptSearch.hits(of: needle, in: text) {
                matches.append(Match(scene: scene.id, take: nil, paragraph: hit.paragraph, location: hit.location, length: hit.length, text: paragraphs[hit.paragraph]))
            }
            guard includingTakes else { continue }
            for take in try takes(for: scene.id) {
                let taken = try takeText(take)
                let takeParagraphs = Prose.paragraphs(taken)
                for hit in ManuscriptSearch.hits(of: needle, in: taken) {
                    matches.append(Match(scene: scene.id, take: take, paragraph: hit.paragraph, location: hit.location, length: hit.length, text: takeParagraphs[hit.paragraph]))
                }
            }
        }
        return matches
    }
}
