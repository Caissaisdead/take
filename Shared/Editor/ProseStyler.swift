import ManuscriptKit
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#else
import AppKit
typealias PlatformFont = NSFont
#endif

/// The look of prose in the editor and the compare pane: one serif face, one
/// measure, so both read as the same text. The phone's lines are shorter, so
/// its type is a point larger and its leading a touch tighter.
@MainActor
enum ProseStyle {
    #if os(iOS)
    static let size: CGFloat = 18
    static let lineHeight: CGFloat = 1.45
    static let labelColor = UIColor.label
    static let secondaryColor = UIColor.secondaryLabel
    static let dimColor = UIColor.tertiaryLabel
    #else
    static let size: CGFloat = 17
    static let lineHeight: CGFloat = 1.5
    static let labelColor = NSColor.labelColor
    static let secondaryColor = NSColor.secondaryLabelColor
    static let dimColor = NSColor.tertiaryLabelColor
    #endif

    static let font: PlatformFont = {
        let system = PlatformFont.systemFont(ofSize: size)
        guard let serif = system.fontDescriptor.withDesign(.serif) else { return system }
        #if os(iOS)
        return UIFont(descriptor: serif, size: size)
        #else
        return NSFont(descriptor: serif, size: size) ?? system
        #endif
    }()

    #if os(iOS)
    static let italic = font.withTrait(.traitItalic)
    static let bold = font.withTrait(.traitBold)
    #else
    static let italic = font.withTrait(.italic)
    static let bold = font.withTrait(.bold)
    #endif

    static let paragraph = makeParagraphStyle(alignment: .natural)
    static let centred = makeParagraphStyle(alignment: .center)

    static let base: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: labelColor,
        .paragraphStyle: paragraph,
    ]

    private static func makeParagraphStyle(alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacing = 14
        style.alignment = alignment
        return style
    }
}

private extension PlatformFont {
    #if os(iOS)
    func withTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(trait)) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
    #else
    func withTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
    #endif
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

/// Restyles only the paragraphs an edit touched, so a keystroke in a 20k-word
/// scene never pays for the whole document. Attributes are reset to the base and
/// the Markdown emphasis markers re-read on each pass; nothing is cached.
@MainActor
final class ProseStyler: NSObject, @MainActor NSTextStorageDelegate {
    /// Set while `ProseTextView.setText` replaces the document, which restyles
    /// the whole thing once itself.
    var isSuspended = false

    private let bold = MarkdownEmphasis.bold
    private let italic = MarkdownEmphasis.italic
    private let underscoreItalic = MarkdownEmphasis.underscoreItalic
    private let note = Prose.notePattern

    func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        // Attribute-only edits are our own; restyling them again would loop.
        guard !isSuspended, editedMask.contains(.editedCharacters) else { return }
        restyle(storage, in: editedRange)
    }

    func restyle(_ storage: NSTextStorage, in range: NSRange) {
        let text = storage.mutableString
        let paragraphs = text.paragraphRange(for: range)
        storage.setAttributes(ProseStyle.base, range: paragraphs)
        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, body, enclosing, _ in
            self.style(paragraph: body, enclosing: enclosing, in: storage)
        }
    }

    private func style(paragraph: NSRange, enclosing: NSRange, in storage: NSTextStorage) {
        let text = storage.mutableString.substring(with: paragraph)
        if MarkdownEmphasis.isSceneBreak(text) {
            storage.addAttributes([.paragraphStyle: ProseStyle.centred, .foregroundColor: ProseStyle.dimColor], range: enclosing)
            return
        }
        apply(bold, font: ProseStyle.bold, to: text, offset: paragraph.location, in: storage)
        apply(italic, font: ProseStyle.italic, to: text, offset: paragraph.location, in: storage)
        apply(underscoreItalic, font: ProseStyle.italic, to: text, offset: paragraph.location, in: storage)
        // A writer's note, brackets and all, steps back from the prose.
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for match in note.matches(in: text, range: whole) {
            storage.addAttributes([.font: ProseStyle.italic, .foregroundColor: ProseStyle.dimColor], range: shifted(match.range, by: paragraph.location))
        }
    }

    private func apply(_ pattern: NSRegularExpression, font: PlatformFont, to text: String, offset: Int, in storage: NSTextStorage) {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for match in pattern.matches(in: text, range: whole) {
            let outer = match.range
            let inner = match.range(at: 1)
            let opening = NSRange(location: outer.location, length: inner.location - outer.location)
            let closing = NSRange(location: inner.location + inner.length, length: outer.location + outer.length - inner.location - inner.length)
            storage.addAttribute(.font, value: font, range: shifted(inner, by: offset))
            for marker in [opening, closing] {
                storage.addAttribute(.foregroundColor, value: ProseStyle.dimColor, range: shifted(marker, by: offset))
            }
        }
    }

    private func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}

