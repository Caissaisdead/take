import Foundation

/// A file an export writes, by path relative to the folder the writer chose.
public struct ExportFile: Hashable, Sendable {
    public var path: String
    public var data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }

    public var text: String { String(decoding: data, as: UTF8.self) }
}

/// The draft as Markdown: one file per scene under numbered chapter folders
/// (and part folders, when the manuscript uses parts), plus the whole draft in
/// one file at the root. Numbers follow the manifest's order at export time, so
/// the folder reads in order wherever it is opened.
public enum MarkdownExport {
    /// Every file, combined first. `text` reads a scene as stored.
    public static func files(for manuscript: Manuscript, text: (SceneID) throws -> String) rethrows -> [ExportFile] {
        var files = [ExportFile(path: "\(fileName(manuscript.title, fallback: "Manuscript")).md", data: Data(try combined(manuscript, text: text).utf8))]
        let showsParts = usesParts(manuscript)
        var chapterNumber = 0
        for (p, part) in manuscript.parts.enumerated() {
            let partFolder = showsParts ? "\(number(p + 1)) \(fileName(part.title, fallback: "Part \(p + 1)"))/" : ""
            for chapter in part.chapters {
                chapterNumber += 1
                let folder = partFolder + "\(number(chapterNumber)) \(fileName(chapter.title, fallback: "Chapter \(chapterNumber)"))"
                for (s, scene) in chapter.scenes.enumerated() {
                    let name = "\(number(s + 1)) \(fileName(scene.title, fallback: "Scene \(s + 1)")).md"
                    files.append(ExportFile(path: "\(folder)/\(name)", data: Data(Prose.normalize(try text(scene.id)).utf8)))
                }
            }
        }
        return files
    }

    /// The whole draft as one Markdown document: the title, a heading per part
    /// when parts are used, a heading per chapter, and `* * *` between scenes.
    /// Scene titles are the writer's own labels and never appear.
    public static func combined(_ manuscript: Manuscript, text: (SceneID) throws -> String) rethrows -> String {
        var out = "# \(heading(manuscript.title, fallback: "Untitled"))\n"
        let showsParts = usesParts(manuscript)
        let chapterMark = showsParts ? "###" : "##"
        var chapterNumber = 0
        for (p, part) in manuscript.parts.enumerated() {
            if showsParts {
                out += "\n## \(heading(part.title, fallback: "Part \(p + 1)"))\n"
            }
            for chapter in part.chapters {
                chapterNumber += 1
                out += "\n\(chapterMark) \(heading(chapter.title, fallback: "Chapter \(chapterNumber)"))\n"
                var first = true
                for scene in chapter.scenes {
                    let body = Prose.normalize(try text(scene.id))
                    guard !body.isEmpty else { continue }
                    out += first ? "\n" : "\n* * *\n\n"
                    out += body
                    first = false
                }
            }
        }
        return out
    }

    /// Parts are shown when there is more than one or any has a title.
    static func usesParts(_ manuscript: Manuscript) -> Bool {
        manuscript.parts.count > 1 || manuscript.parts.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func number(_ n: Int) -> String {
        n < 10 ? "0\(n)" : "\(n)"
    }

    /// A title as a file or folder name: no slashes or colons, no control
    /// characters, trimmed, never empty and never starting with a dot.
    public static func fileName(_ title: String, fallback: String) -> String {
        var name = ""
        for scalar in title.unicodeScalars {
            switch scalar {
            case "/", ":", "\\": name.append("-")
            default:
                if scalar.properties.generalCategory != .control { name.unicodeScalars.append(scalar) }
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? fallback : String(name.prefix(120))
    }

    private static func heading(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
