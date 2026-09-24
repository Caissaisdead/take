import AppKit
import SwiftUI

/// The scene editor in SwiftUI: a scroll view around a `ProseTextView`. The text
/// is pushed into the view only when `loadToken` changes, never by comparing
/// strings, so a keystroke costs nothing proportional to the document and never
/// resets the caret. Edits are reported without a payload; the owner reads the
/// text back through the view handed over in `onReady`.
struct EditorView: NSViewRepresentable {
    var text: String
    var loadToken: Int
    var onChange: () -> Void = {}
    var onLoad: (_ millis: Double) -> Void = { _ in }
    /// Receives the text view once it exists, for the in-app bench.
    var onReady: (ProseTextView) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = ProseTextView.make()
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        let coordinator = context.coordinator
        textView.onTextChange = { coordinator.parent.onChange() }
        // Deferred: setText runs inside updateNSView, and the callback mutates model state.
        textView.onLoad = { millis in
            DispatchQueue.main.async { coordinator.parent.onLoad(millis) }
        }
        coordinator.textView = textView
        coordinator.loadedToken = loadToken
        scrollView.documentView = textView
        textView.setText(text)
        DispatchQueue.main.async { coordinator.parent.onReady(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView, coordinator.loadedToken != loadToken else { return }
        coordinator.loadedToken = loadToken
        textView.setText(text)
    }

    final class Coordinator {
        var parent: EditorView
        weak var textView: ProseTextView?
        var loadedToken = 0

        init(parent: EditorView) {
            self.parent = parent
        }
    }
}
