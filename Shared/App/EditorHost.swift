import Foundation

/// What the model asks of whatever view is editing the scene: the text as it
/// stands, and a selection made in place without a reload. The Mac's
/// NSTextView and the iPhone's UITextView each answer for themselves.
@MainActor
protocol EditorHost: AnyObject {
    /// The text as the view holds it now, one paragraph per line.
    var currentText: String { get }
    /// Selects `range` (clipped to the text), scrolls to it and takes focus.
    func reveal(_ range: NSRange)
}
