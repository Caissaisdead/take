import Foundation

/// A manuscript read from outside the app, ready to become a project.
public struct Draft: Hashable, Sendable {
    public struct Scene: Hashable, Sendable {
        public var title: String
        public var text: String

        public init(title: String, text: String) {
            self.title = title
            self.text = text
        }
    }

    public struct Chapter: Hashable, Sendable {
        public var title: String
        public var scenes: [Scene]

        public init(title: String, scenes: [Scene]) {
            self.title = title
            self.scenes = scenes
        }
    }

    public var title: String
    public var chapters: [Chapter]

    public init(title: String, chapters: [Chapter]) {
        self.title = title
        self.chapters = chapters
    }

    public var scenes: [Scene] { chapters.flatMap(\.scenes) }
}

/// Reading a draft out of Markdown or a folder of it.
public enum ManuscriptImport {
    /// One Markdown text: a `#` line is the title, `##` begins a chapter,
    /// `###` a scene, and `* * *` or `---` a scene break. Text before any
    /// heading goes in a first chapter; a text with no headings at all is one
    /// chapter with its scenes cut at the breaks. Scenes without a heading are
    /// numbered within their chapter.
    public static func split(markdown text: String, fallbackTitle: String) -> Draft {
        var title: String?
        var chapters: [Draft.Chapter] = []
        var scenes: [Draft.Scene] = []
        var chapterTitle = ""
        var sceneTitle = ""
        var body: [String] = []

        func closeScene() {
            if !body.isEmpty || !sceneTitle.isEmpty {
                scenes.append(Draft.Scene(title: sceneTitle, text: Prose.join(body)))
            }
            sceneTitle = ""
            body = []
        }
        func closeChapter() {
            closeScene()
            if !scenes.isEmpty || !chapterTitle.isEmpty {
                chapters.append(Draft.Chapter(title: chapterTitle, scenes: scenes))
            }
            scenes = []
            chapterTitle = ""
        }

        for paragraph in Prose.paragraphs(text) {
            if let heading = heading(paragraph, level: 1) {
                if title == nil, chapters.isEmpty, scenes.isEmpty, body.isEmpty, chapterTitle.isEmpty {
                    title = heading
                } else {
                    closeChapter()
                    chapterTitle = heading
                }
            } else if let heading = heading(paragraph, level: 2) {
                closeChapter()
                chapterTitle = heading
            } else if let heading = heading(paragraph, level: 3) {
                closeScene()
                sceneTitle = heading
            } else if MarkdownEmphasis.isSceneBreak(paragraph) {
                closeScene()
            } else {
                body.append(paragraph)
            }
        }
        closeChapter()
        return numbered(Draft(title: title ?? fallbackTitle, chapters: chapters))
    }

    /// Files by their paths within a folder: a folder is a chapter and a file
    /// in it a scene, each in name order; files at the top level make one
    /// chapter. A leading number on a name (`01 `, `01-`, `01_`) and the
    /// extension come off the title.
    public static func draft(fromFiles files: [(path: String, text: String)], title: String) -> Draft {
        var byFolder: [String: [(name: String, text: String)]] = [:]
        for file in files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let name = parts.last else { continue }
            let folder = parts.dropLast().joined(separator: "/")
            byFolder[folder, default: []].append((name, file.text))
        }
        let chapters = byFolder.keys.sorted(by: numericOrder).map { folder in
            let scenes = byFolder[folder]!.sorted { numericOrder($0.name, $1.name) }
                .map { Draft.Scene(title: cleanName($0.name), text: Prose.normalize($0.text)) }
            return Draft.Chapter(title: folder.isEmpty ? "" : cleanName(folder.split(separator: "/").last.map(String.init) ?? folder), scenes: scenes)
        }
        return numbered(Draft(title: title, chapters: chapters))
    }

    /// `#`, `##` or `###` and a space, then the heading, trimmed.
    static func heading(_ paragraph: String, level: Int) -> String? {
        let marks = String(repeating: "#", count: level) + " "
        guard paragraph.hasPrefix(marks), !paragraph.hasPrefix(marks.dropLast() + "#") else { return nil }
        return String(paragraph.dropFirst(marks.count)).trimmingCharacters(in: .whitespaces)
    }

    /// A file or folder name as a title: the leading number, its separator
    /// and the extension gone.
    public static func cleanName(_ name: String) -> String {
        var title = name
        if let dot = title.lastIndex(of: "."), dot != title.startIndex {
            title = String(title[..<dot])
        }
        let stripped = title.replacingOccurrences(of: #"^\d+[\s._-]+"#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespaces).isEmpty ? title : stripped.trimmingCharacters(in: .whitespaces)
    }

    /// `02 b` before `10 a`: names compare by their numbers where they have them.
    static func numericOrder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }

    /// Untitled chapters and scenes get numbers, and chapters with nothing in
    /// them go.
    private static func numbered(_ draft: Draft) -> Draft {
        var draft = draft
        draft.chapters = draft.chapters.filter { !$0.scenes.isEmpty }
        for c in draft.chapters.indices {
            if draft.chapters[c].title.isEmpty { draft.chapters[c].title = "Chapter \(c + 1)" }
            for s in draft.chapters[c].scenes.indices where draft.chapters[c].scenes[s].title.isEmpty {
                draft.chapters[c].scenes[s].title = "Scene \(s + 1)"
            }
        }
        return draft
    }
}

extension ProjectStore {
    /// Makes a project at `url` and fills it from the draft in one commit
    /// after the first.
    public static func create(at url: URL, draft: Draft, author: Signature) throws -> ProjectStore {
        let store = try create(at: url, title: draft.title, author: author)
        try store.add(draft)
        return store
    }

    /// Every chapter and scene of the draft, at the end, in one commit.
    public func add(_ draft: Draft) throws {
        var manuscript = try manifest()
        let head = try mainHead()
        for chapter in draft.chapters {
            let made = try newChapter(title: chapter.title, in: &manuscript)
            try manuscript.append(made, toPart: try Self.destinationPart(nil, in: &manuscript))
            for scene in chapter.scenes {
                let path = try scenePath(for: scene.title, in: manuscript.chapter(made.id)!, of: manuscript, at: head)
                let ref = SceneRef(id: SceneID(), title: scene.title, path: path)
                try manuscript.insert(ref, inChapter: made.id)
                try repository.writeWorkingFile(atPath: path, data: stored(scene.text))
            }
        }
        try writeManifest(manuscript)
        try commitIndex(message: "Import \(Self.label(draft.title))", parents: [head])
    }

    /// A project folder that lost its repository, or never had one, taken in
    /// as it stands: the manifest is read, every file it names is staged with
    /// it, and the first commit is made. Refused when the manifest or a file
    /// it names is missing.
    public static func adopt(at url: URL, author: Signature) throws -> ProjectStore {
        let manifestURL = url.appendingPathComponent(Manuscript.manifestPath)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw ProjectStoreError.missingFile(Manuscript.manifestPath) }
        let data = try Data(contentsOf: manifestURL)
        struct Stamp: Decodable { var format: Int? }
        let format = try JSONDecoder().decode(Stamp.self, from: data).format ?? 1
        guard Manuscript.readableFormats.contains(format) else { throw ProjectStoreError.unsupportedFormat(format) }
        var manuscript = try JSONDecoder().decode(Manuscript.self, from: data)
        manuscript.format = Manuscript.currentFormat
        for scene in manuscript.scenes where !FileManager.default.fileExists(atPath: url.appendingPathComponent(scene.path).path) {
            throw ProjectStoreError.missingFile(scene.path)
        }
        let store = ProjectStore(repository: try Repository.create(at: url), author: author)
        for scene in manuscript.scenes {
            try store.repository.writeWorkingFile(atPath: scene.path, data: try Data(contentsOf: url.appendingPathComponent(scene.path)))
        }
        try store.writeManifest(manuscript)
        try store.commitIndex(message: "Adopt \(label(manuscript.title))", parents: [])
        return store
    }
}
