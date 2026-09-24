import AppKit
import ManuscriptKit

/// The draft as a PDF: the same pages the Word export makes, laid out by
/// AppKit's print system onto Letter with inch margins and paginated by it.
@MainActor
enum PDFWriter {
    enum Failure: LocalizedError {
        case notWritten

        var errorDescription: String? { "The PDF could not be laid out." }
    }

    static func data(for manuscript: Manuscript, text: (SceneID) throws -> String) throws -> Data {
        let document = try DocxWriter.attributedString(for: manuscript, text: text)

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 72
        info.bottomMargin = 72
        info.leftMargin = 72
        info.rightMargin = 72
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        // TextKit 1 on purpose: the print path paginates it and never shows it.
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(document)
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        textView.sizeToFit()

        let data = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(with: textView, inside: textView.bounds, to: data, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), data.length > 0 else { throw Failure.notWritten }
        return data as Data
    }
}
