import AppKit
import ManuscriptKit

/// The look of prose in the editor and the compare pane: one serif face, one
/// measure, so both read as the same text.
@MainActor
enum ProseStyle {
    static let size: CGFloat = 17

    static let font: NSFont = {
        let system = NSFont.systemFont(ofSize: size)
        guard let serif = system.fontDescriptor.withDesign(.serif),
              let font = NSFont(descriptor: serif, size: size) else { return system }
        return font
    }()

    static let italic = font.withTrait(.italic)
    static let bold = font.withTrait(.bold)

    static let paragraph = makeParagraphStyle(alignment: .natural)
    static let centred = makeParagraphStyle(alignment: .center)

    static let base: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraph,
    ]

    private static func makeParagraphStyle(alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.5
        style.paragraphSpacing = 14
        style.alignment = alignment
        return style
    }
}

private extension NSFont {
    func withTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
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
            storage.addAttributes([.paragraphStyle: ProseStyle.centred, .foregroundColor: NSColor.tertiaryLabelColor], range: enclosing)
            return
        }
        apply(bold, font: ProseStyle.bold, to: text, offset: paragraph.location, in: storage)
        apply(italic, font: ProseStyle.italic, to: text, offset: paragraph.location, in: storage)
        apply(underscoreItalic, font: ProseStyle.italic, to: text, offset: paragraph.location, in: storage)
    }

    private func apply(_ pattern: NSRegularExpression, font: NSFont, to text: String, offset: Int, in storage: NSTextStorage) {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for match in pattern.matches(in: text, range: whole) {
            let outer = match.range
            let inner = match.range(at: 1)
            let opening = NSRange(location: outer.location, length: inner.location - outer.location)
            let closing = NSRange(location: inner.location + inner.length, length: outer.location + outer.length - inner.location - inner.length)
            storage.addAttribute(.font, value: font, range: shifted(inner, by: offset))
            for marker in [opening, closing] {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: shifted(marker, by: offset))
            }
        }
    }

    private func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}

/// The scene editor: an NSTextView on TextKit 2. `layoutManager` is never read
/// here or anywhere else, because reading it silently rebuilds the view on
/// TextKit 1.
final class ProseTextView: NSTextView {
    /// Fired from `didChangeText` for user edits only, never for `setText`. No
    /// payload: reading `string` bridges the whole document, and a keystroke
    /// must not cost the document's length.
    var onTextChange: () -> Void = {}
    /// Receives how long `setText` took, in milliseconds, after each load.
    var onLoad: (_ millis: Double) -> Void = { _ in }

    private let styler = ProseStyler()
    private var isSettingText = false

    static func make() -> ProseTextView {
        let view = ProseTextView(usingTextLayoutManager: true)
        view.configure()
        return view
    }

    private func configure() {
        isRichText = true
        allowsUndo = true
        isContinuousSpellCheckingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = true
        isAutomaticDashSubstitutionEnabled = true
        isAutomaticTextReplacementEnabled = false
        usesFontPanel = false
        usesRuler = false
        isRulerVisible = false
        textContainerInset = NSSize(width: 32, height: 24)

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude)

        font = ProseStyle.font
        textColor = .labelColor
        defaultParagraphStyle = ProseStyle.paragraph
        typingAttributes = ProseStyle.base
        textStorage?.delegate = styler
    }

    /// Replaces the whole document, restyles it once and reports the time taken,
    /// in milliseconds. Layout is not forced: TextKit 2 lays out the viewport
    /// lazily, and that laziness is part of what the spike measures.
    @discardableResult
    func setText(_ text: String) -> Double {
        guard let storage = textStorage else { return 0 }
        let elapsed = ContinuousClock().measure {
            isSettingText = true
            styler.isSuspended = true
            defer {
                isSettingText = false
                styler.isSuspended = false
            }
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            styler.restyle(storage, in: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            undoManager?.removeAllActions()
            setSelectedRange(NSRange(location: 0, length: 0))
        }
        scrollToBeginningOfDocument(nil)
        // The first viewport layout works from estimated heights and can leave the
        // scroll position mid-document; settle at the top again once it has run.
        DispatchQueue.main.async { [weak self] in
            self?.setSelectedRange(NSRange(location: 0, length: 0))
            self?.scrollToBeginningOfDocument(nil)
        }
        onLoad(elapsed.milliseconds)
        return elapsed.milliseconds
    }

    override func didChangeText() {
        super.didChangeText()
        guard !isSettingText else { return }
        onTextChange()
    }
}
