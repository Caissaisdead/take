import ManuscriptKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The draft as styled text for a document: title, part and chapter
/// headings, a scene break between scenes, emphasis as bold and italic with
/// the markers gone. The Word and PDF writers on either platform lay this
/// out; it never reaches the screen.
enum ManuscriptLayout {
    static let bodyFont: PlatformFont = PlatformFont(name: "Georgia", size: 12) ?? PlatformFont.systemFont(ofSize: 12)

    static func attributedString(for manuscript: Manuscript, text: (SceneID) throws -> String) rethrows -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        out.append(heading(manuscript.title.isEmpty ? "Untitled" : manuscript.title, size: 20, centred: true, spaceBefore: 0))
        let showsParts = manuscript.usesParts
        var chapterNumber = 0
        for (p, part) in manuscript.parts.enumerated() {
            if showsParts {
                let title = part.title.trimmingCharacters(in: .whitespaces)
                out.append(heading(title.isEmpty ? "Part \(p + 1)" : title, size: 16, centred: true, spaceBefore: 36))
            }
            for chapter in part.chapters {
                chapterNumber += 1
                let title = chapter.title.trimmingCharacters(in: .whitespaces)
                out.append(heading(title.isEmpty ? "Chapter \(chapterNumber)" : title, size: 14, centred: false, spaceBefore: 30))
                var first = true
                for scene in chapter.scenes {
                    let paragraphs = Prose.paragraphs(Prose.withoutNotes(try text(scene.id)))
                    guard !paragraphs.isEmpty else { continue }
                    if !first { out.append(sceneBreak()) }
                    first = false
                    for paragraph in paragraphs {
                        out.append(MarkdownEmphasis.isSceneBreak(paragraph) ? sceneBreak() : body(paragraph))
                    }
                }
            }
        }
        return out
    }

    private static func heading(_ title: String, size: CGFloat, centred: Bool, spaceBefore: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = centred ? .center : .left
        style.paragraphSpacingBefore = spaceBefore
        style.paragraphSpacing = 12
        let font = bodyFont.withSize(size).adding(.bold)
        return NSAttributedString(string: title + "\n", attributes: [.font: font, .paragraphStyle: style])
    }

    private static func sceneBreak() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 12
        return NSAttributedString(string: "* * *\n", attributes: [.font: bodyFont, .paragraphStyle: style])
    }

    private static func body(_ paragraph: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 24
        style.lineHeightMultiple = 1.15
        style.paragraphSpacing = 0
        let stripped = MarkdownEmphasis.strip(paragraph)
        let out = NSMutableAttributedString(string: stripped.text + "\n", attributes: [.font: bodyFont, .paragraphStyle: style])
        for run in stripped.runs {
            guard run.range.location + run.range.length <= out.length else { continue }
            let current = out.attribute(.font, at: run.range.location, effectiveRange: nil) as? PlatformFont ?? bodyFont
            out.addAttribute(.font, value: current.adding(run.trait == .bold ? .bold : .italic), range: run.range)
        }
        return out
    }
}

extension PlatformFont {
    enum Trait { case bold, italic }

    /// The same face with the trait added, as far as the family has it.
    func adding(_ trait: Trait) -> PlatformFont {
        #if canImport(UIKit)
        let symbolic: UIFontDescriptor.SymbolicTraits = trait == .bold ? .traitBold : .traitItalic
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(symbolic)) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #else
        let symbolic: NSFontDescriptor.SymbolicTraits = trait == .bold ? .bold : .italic
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(symbolic))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
        #endif
    }
}
