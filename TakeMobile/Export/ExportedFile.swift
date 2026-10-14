import SwiftUI
import UniformTypeIdentifiers

/// Bytes on their way to the Files app.
struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf, UTType("net.daringfireball.markdown") ?? .plainText]

    let data: Data
    let type: UTType

    init(_ document: ProjectModel.ExportDocument) {
        data = document.data
        type = document.kind == .pdf ? .pdf : (UTType("net.daringfireball.markdown") ?? .plainText)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
