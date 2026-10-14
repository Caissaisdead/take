import AppKit
import ManuscriptKit

/// The scene editor: an NSTextView on TextKit 2. `layoutManager` is never read
/// here or anywhere else, because reading it silently rebuilds the view on
/// TextKit 1.
final class ProseTextView: NSTextView, EditorHost {
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
        apply(Accent.current)
    }

    /// The caret and the selection in the writer's accent.
    func apply(_ accent: Accent) {
        insertionPointColor = accent.platformColor
        selectedTextAttributes = [.backgroundColor: accent.platformColor.withAlphaComponent(0.22)]
    }

    // MARK: - EditorHost

    var currentText: String { string }

    func reveal(_ range: NSRange) {
        show(range)
        window?.makeFirstResponder(self)
    }

    /// Replaces the whole document, restyles it once and reports the time taken,
    /// in milliseconds. Layout is not forced: TextKit 2 lays out the viewport
    /// lazily, and that laziness is part of what the spike measures. The caret
    /// lands at the top, or on `selecting` when a range is asked for.
    @discardableResult
    func setText(_ text: String, selecting: NSRange? = nil) -> Double {
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
        }
        show(selecting)
        // The first viewport layout works from estimated heights and can leave the
        // scroll position mid-document; settle again once it has run.
        DispatchQueue.main.async { [weak self] in
            self?.show(selecting)
        }
        onLoad(elapsed.milliseconds)
        return elapsed.milliseconds
    }

    /// Selects `range` and scrolls to it, or goes to the top for nil. A range
    /// past the end of the text is clipped to it.
    func show(_ range: NSRange?) {
        let length = (string as NSString).length
        guard let range, range.location <= length else {
            setSelectedRange(NSRange(location: 0, length: 0))
            scrollToBeginningOfDocument(nil)
            return
        }
        let clipped = NSRange(location: range.location, length: min(range.length, length - range.location))
        setSelectedRange(clipped)
        scrollRangeToVisible(clipped)
    }

    override func didChangeText() {
        super.didChangeText()
        guard !isSettingText else { return }
        onTextChange()
    }
}
