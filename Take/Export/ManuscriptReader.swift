import AppKit
import ManuscriptKit
import UniformTypeIdentifiers

/// Reads a manuscript from a file or a folder into a `Draft`. Markdown and
/// text go to the splitter as they are; a Word document is read through
/// AppKit and its headings guessed: a paragraph that is bold throughout, or
/// that begins "Chapter" or "Part", becomes a chapter heading.
enum ManuscriptReader {
    enum Failure: LocalizedError {
        case unreadable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "\(name) could not be read as a manuscript."
            case .empty: return "There is no text in it to import."
            }
        }
    }

    static func draft(from url: URL) throws -> Draft {
        let title = ManuscriptImport.cleanName(url.lastPathComponent)
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let draft: Draft
        if isFolder.boolValue {
            draft = ManuscriptImport.draft(fromFiles: try files(in: url), title: title)
        } else if url.pathExtension.lowercased() == "docx" {
            draft = ManuscriptImport.split(markdown: try markdown(fromWord: url), fallbackTitle: title)
        } else {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Failure.unreadable(url.lastPathComponent) }
            draft = ManuscriptImport.split(markdown: text, fallbackTitle: title)
        }
        guard draft.scenes.contains(where: { !$0.text.isEmpty }) else { throw Failure.empty }
        return draft
    }

    /// Every Markdown or text file under the folder, by its path within it.
    private static func files(in folder: URL) throws -> [(path: String, text: String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw Failure.unreadable(folder.lastPathComponent)
        }
        var files: [(path: String, text: String)] = []
        let root = folder.standardizedFileURL.path
        for case let url as URL in walker {
            guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files.append((path, text))
        }
        return files
    }

    /// A Word document as Markdown for the splitter.
    private static func markdown(fromWord url: URL) throws -> String {
        guard let document = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) else {
            throw Failure.unreadable(url.lastPathComponent)
        }
        var lines: [String] = []
        let whole = document.string as NSString
        whole.enumerateSubstrings(in: NSRange(location: 0, length: whole.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let text = whole.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            if isHeading(text, in: document, at: range) {
                lines.append("## " + text)
            } else {
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n\n") + "\n"
    }

    private static func isHeading(_ text: String, in document: NSAttributedString, at range: NSRange) -> Bool {
        if text.range(of: #"^(chapter|part)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        guard Prose.wordCount(text) <= 12 else { return false }
        var bold = true
        document.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.bold) else {
                bold = false
                stop.pointee = true
                return
            }
        }
        return bold
    }
}
