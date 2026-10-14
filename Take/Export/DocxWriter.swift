import AppKit
import ManuscriptKit

/// The draft as a Word document, through AppKit's own Office Open XML writer.
/// Same shape as the Markdown export: title, part and chapter headings, a
/// scene break between scenes, emphasis as bold and italic with the markers
/// gone.
enum DocxWriter {
    static func data(for manuscript: Manuscript, text: (SceneID) throws -> String) throws -> Data {
        let document = try ManuscriptLayout.attributedString(for: manuscript, text: text)
        return try document.data(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML, .title: manuscript.title])
    }
}
