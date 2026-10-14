import SwiftUI
import UIKit

/// The scene editor in SwiftUI, the phone's twin of the Mac's `EditorView`:
/// the text is pushed into the view only when `loadToken` changes, never by
/// comparing strings, so a keystroke costs nothing proportional to the
/// document and never resets the caret.
struct MobileEditorView: UIViewRepresentable {
    var text: String
    var loadToken: Int
    var selection: NSRange? = nil
    var accent: Accent = .blue
    var onChange: () -> Void = {}
    var onLoad: (_ millis: Double) -> Void = { _ in }
    var onReady: (ProseUITextView) -> Void = { _ in }
    var onDismantle: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ProseUITextView {
        let textView = ProseUITextView.make()
        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.onTextChange = { coordinator.parent.onChange() }
        textView.onLoad = { millis in
            DispatchQueue.main.async { coordinator.parent.onLoad(millis) }
        }
        textView.inputAccessoryView = EditorAccessoryBar(host: textView)
        coordinator.textView = textView
        coordinator.loadedToken = loadToken
        textView.setText(text, selecting: selection)
        DispatchQueue.main.async { coordinator.parent.onReady(textView) }
        return textView
    }

    func updateUIView(_ textView: ProseUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.appliedAccent != accent {
            coordinator.appliedAccent = accent
            textView.apply(accent)
        }
        guard coordinator.loadedToken != loadToken else { return }
        coordinator.loadedToken = loadToken
        textView.setText(text, selecting: selection)
    }

    static func dismantleUIView(_ textView: ProseUITextView, coordinator: Coordinator) {
        coordinator.parent.onDismantle(textView.text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MobileEditorView
        weak var textView: ProseUITextView?
        var loadedToken = 0
        var appliedAccent: Accent = .blue

        init(parent: MobileEditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? ProseUITextView, !view.isSettingText else { return }
            view.onTextChange()
        }
    }
}
