import UIKit
import CoreText
import ManuscriptKit

/// The draft as a PDF: the same pages the Mac makes, Letter with inch
/// margins, paginated by Core Text.
enum PDFRenderer {
    static func data(for manuscript: Manuscript, text: (SceneID) throws -> String) throws -> Data {
        let document = try ManuscriptLayout.attributedString(for: manuscript, text: text)
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 72
        let box = page.insetBy(dx: margin, dy: margin)
        let framesetter = CTFramesetterCreateWithAttributedString(document)
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: UIGraphicsPDFRendererFormat())
        return renderer.pdfData { context in
            var start = 0
            let length = document.length
            repeat {
                context.beginPage()
                let path = CGPath(rect: box, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
                let cg = context.cgContext
                // Core Text draws with the origin at the bottom; flip for it.
                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: page.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()
                let drawn = CTFrameGetVisibleStringRange(frame)
                guard drawn.length > 0 else { break }
                start = drawn.location + drawn.length
            } while start < length
        }
    }
}
