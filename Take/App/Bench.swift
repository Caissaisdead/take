import AppKit
import ManuscriptKit

/// The spike's go/no-go measurement, run in the real window without any UI
/// automation: how long a text takes to load, and what one typed character
/// costs once styling, viewport layout and drawing are all forced to happen.
@MainActor
struct Bench {
    struct Stats: Codable {
        var count: Int
        var p50: Double
        var p95: Double
        var max: Double

        init(millis: [Double]) {
            let sorted = millis.sorted()
            func percentile(_ q: Double) -> Double {
                guard !sorted.isEmpty else { return 0 }
                return sorted[Swift.max(0, Swift.min(sorted.count - 1, Int((Double(sorted.count) * q).rounded(.up)) - 1))]
            }
            count = sorted.count
            p50 = percentile(0.5)
            p95 = percentile(0.95)
            max = sorted.last ?? 0
        }
    }

    /// One keystroke's cost, whole and in its three parts: the insert (storage
    /// edit, styler, and the model's round trip through `didChangeText`), the
    /// viewport layout, and the display pass (which is where SwiftUI's own
    /// update lands as well).
    struct Phase: Codable {
        var total: Stats
        var insert: Stats
        var layout: Stats
        var display: Stats
    }

    struct Sample: Codable {
        var label: String
        var words: Int
        var characters: Int
        var loadMillis: Double
        /// Where the middle-of-document typing began: the start of a paragraph.
        var middleLocation: Int
        var middle: Phase
        var end: Phase
        /// `textLayoutManager` still present at the end, so the view never fell back to TextKit 1.
        var textKit2: Bool
    }

    struct Result: Codable {
        var date: Date
        var samples: [Sample]
    }

    static let typed = 120
    static let warmUp = 5
    /// What gets typed, character by character; spaces included so word breaks
    /// and spell checking happen as they would for a writer.
    static let phrase = "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife. "

    let textView: ProseTextView

    /// Loads straight into the view: the editor only reloads on its owner's load
    /// token, so nothing pushes the old text back while the bench runs.
    func run(_ texts: [(label: String, text: String)]) -> Result {
        var samples: [Sample] = []
        for (label, text) in texts {
            let loadMillis = textView.setText(text)
            let whole = textView.string as NSString
            let middle = whole.paragraphRange(for: NSRange(location: whole.length / 2, length: 0)).location
            let middleStats = type(at: middle)
            let endStats = type(at: (textView.string as NSString).length)
            samples.append(Sample(
                label: label,
                words: Prose.wordCount(text),
                characters: textView.string.count,
                loadMillis: loadMillis,
                middleLocation: middle,
                middle: middleStats,
                end: endStats,
                textKit2: textView.textLayoutManager != nil
            ))
        }
        return Result(date: Date(), samples: samples)
    }

    /// Types the phrase one character at a time from `location`, each keystroke
    /// followed by a full viewport layout and display, and returns the counted
    /// keystrokes' timings.
    private func type(at location: Int) -> Phase {
        let caret = NSRange(location: location, length: 0)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
        let clock = ContinuousClock()
        var total: [Double] = [], insert: [Double] = [], layout: [Double] = [], display: [Double] = []
        for index in 0..<(Self.warmUp + Self.typed) {
            let character = String(Self.phrase[Self.phrase.index(Self.phrase.startIndex, offsetBy: index % Self.phrase.count)])
            let start = clock.now
            // The same entry point key events reach, so the styler and the model see it as typing.
            textView.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0))
            let inserted = clock.now
            textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
            let laidOut = clock.now
            textView.displayIfNeeded()
            textView.window?.displayIfNeeded()
            // Layer-backed drawing lands at commit time, so commit before the clock stops.
            CATransaction.flush()
            let displayed = clock.now
            guard index >= Self.warmUp else { continue }
            total.append((displayed - start).milliseconds)
            insert.append((inserted - start).milliseconds)
            layout.append((laidOut - inserted).milliseconds)
            display.append((displayed - laidOut).milliseconds)
        }
        return Phase(total: Stats(millis: total), insert: Stats(millis: insert), layout: Stats(millis: layout), display: Stats(millis: display))
    }
}
