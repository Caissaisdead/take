import AppKit
import SwiftUI
import ManuscriptKit

/// The compare pane: a summary line over the rendered diff. Equatable so the
/// inspector only re-renders the diff when the diff itself changes, not on every
/// keystroke that redraws the window.
struct CompareView: View, Equatable {
    let diff: ProseDiff?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            if let diff {
                DiffTextView(content: DiffRenderer.render(diff))
            } else {
                ContentUnavailableView(
                    "Nothing to compare",
                    systemImage: "doc.on.doc",
                    description: Text("Pick a version or milestone above. Main compares with its previous version once it has one.")
                )
            }
        }
    }

    private var summary: String {
        guard let diff else { return "No comparison" }
        let s = diff.summary
        let paragraphs = s.paragraphsChanged == 1 ? "paragraph" : "paragraphs"
        return "\(s.paragraphsChanged) \(paragraphs) changed  +\(s.wordsAdded) −\(s.wordsRemoved) words"
    }
}

/// A read-only TextKit 2 text view for the rendered diff.
private struct DiffTextView: NSViewRepresentable {
    let content: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.textStorage?.setAttributedString(content)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let storage = textView.textStorage,
              !storage.isEqual(to: content) else { return }
        storage.setAttributedString(content)
        textView.scrollToBeginningOfDocument(nil)
    }
}
