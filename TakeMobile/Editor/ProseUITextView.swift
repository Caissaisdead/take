import UIKit
import ManuscriptKit

/// The scene editor: a UITextView on TextKit 2 with the same styler as the
/// Mac. `layoutManager` is never read here or anywhere else, because reading
/// it silently rebuilds the view on TextKit 1.
final class ProseUITextView: UITextView, EditorHost {
    /// Fired from the delegate for user edits only, never for `setText`.
    var onTextChange: () -> Void = {}
    /// Receives how long `setText` took, in milliseconds, after each load.
    var onLoad: (_ millis: Double) -> Void = { _ in }

    private let styler = ProseStyler()
    private(set) var isSettingText = false

    /// The TextKit 2 stack is built by hand: UIKit's
    /// `init(usingTextLayoutManager:)` is a factory initializer, and a
    /// Swift subclass made through it never has its stored properties set.
    static func make() -> ProseUITextView {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        let view = ProseUITextView(frame: .zero, textContainer: container)
        view.configure()
        return view
    }

    private func configure() {
        isEditable = true
        isScrollEnabled = true
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        textContainer.lineFragmentPadding = 0
        allowsEditingTextAttributes = false
        autocorrectionType = .default
        spellCheckingType = .yes
        smartQuotesType = .yes
        smartDashesType = .yes
        smartInsertDeleteType = .no
        font = ProseStyle.font
        textColor = ProseStyle.labelColor
        typingAttributes = ProseStyle.base
        textStorage.delegate = styler
        apply(Accent.current)
    }

    /// The caret and the selection in the writer's accent.
    func apply(_ accent: Accent) {
        tintColor = accent.platformColor
    }

    /// Replaces the whole document, restyles it once and reports the time
    /// taken, in milliseconds. The caret lands at the top, or on `selecting`.
    @discardableResult
    func setText(_ text: String, selecting: NSRange? = nil) -> Double {
        let storage = textStorage
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
        DispatchQueue.main.async { [weak self] in
            self?.show(selecting)
        }
        onLoad(elapsed.milliseconds)
        return elapsed.milliseconds
    }

    /// Selects `range` and scrolls to it, or goes to the top for nil. A
    /// range past the end of the text is clipped to it.
    func show(_ range: NSRange?) {
        let length = (text as NSString).length
        guard let range, range.location <= length else {
            selectedRange = NSRange(location: 0, length: 0)
            setContentOffset(.zero, animated: false)
            return
        }
        let clipped = NSRange(location: range.location, length: min(range.length, length - range.location))
        selectedRange = clipped
        scrollRangeToVisible(clipped)
    }

    /// Pasted text comes in plain, so no outside styling reaches the prose.
    override func paste(_ sender: Any?) {
        if let string = UIPasteboard.general.string {
            insertText(string)
        } else {
            super.paste(sender)
        }
    }

    // MARK: - EditorHost

    var currentText: String { text }

    func reveal(_ range: NSRange) {
        show(range)
        becomeFirstResponder()
    }

    // MARK: - Accessory actions

    /// Wraps the selection in `marker` on both sides, or puts a pair down
    /// with the caret between them.
    func wrapSelection(in marker: String) {
        let selected = selectedRange
        let inner = (text as NSString).substring(with: selected)
        replace(selected, with: marker + inner + marker)
        selectedRange = NSRange(location: selected.location + (marker as NSString).length, length: (inner as NSString).length)
    }

    /// A writer's note around the selection, or an empty one to type into.
    func insertNote() {
        let selected = selectedRange
        let inner = (text as NSString).substring(with: selected)
        replace(selected, with: "[[" + inner + "]]")
        selectedRange = NSRange(location: selected.location + 2, length: (inner as NSString).length)
    }

    /// A scene break on a line of its own.
    func insertSceneBreak() {
        let whole = text as NSString
        let caret = selectedRange.location
        let atLineStart = caret == 0 || whole.character(at: caret - 1) == 0x0A
        let atLineEnd = caret >= whole.length || whole.character(at: caret) == 0x0A
        let piece = (atLineStart ? "" : "\n") + "* * *" + (atLineEnd ? "\n" : "\n")
        replace(selectedRange, with: piece)
    }

    enum Direction { case previous, next }

    /// Puts the caret at the start of the paragraph before or after this one.
    func moveToParagraph(_ direction: Direction) {
        let whole = text as NSString
        let current = whole.paragraphRange(for: NSRange(location: min(selectedRange.location, whole.length), length: 0))
        let target: NSRange
        switch direction {
        case .previous:
            guard current.location > 0 else { return }
            target = whole.paragraphRange(for: NSRange(location: current.location - 1, length: 0))
        case .next:
            let after = current.location + current.length
            guard after < whole.length else { return }
            target = whole.paragraphRange(for: NSRange(location: after, length: 0))
        }
        selectedRange = NSRange(location: target.location, length: 0)
        scrollRangeToVisible(selectedRange)
    }

    private func replace(_ range: NSRange, with string: String) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        replace(textRange, withText: string)
    }
}
