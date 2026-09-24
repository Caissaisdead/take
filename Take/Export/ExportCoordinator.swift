import AppKit
import UniformTypeIdentifiers
import ManuscriptKit

/// Runs the save panels for exports and writes what comes back. The sandbox
/// grants the app the folder or file the panel returns, and nothing else.
@MainActor
enum ExportCoordinator {
    /// Asks where to put a folder of Markdown and writes `files` under it. The
    /// folder is created fresh or, if it exists, its matching paths overwritten.
    static func exportMarkdown(_ files: [ExportFile], suggestedName: String) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export as Markdown"
        panel.message = "A folder with one file per scene, and the whole draft in one file."
        panel.prompt = "Export"
        panel.nameFieldLabel = "Folder name:"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.showsTagField = false
        guard await panel.begin() == .OK, let folder = panel.url else { return nil }

        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            let url = folder.appendingPathComponent(file.path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url, options: .atomic)
        }
        return folder
    }

    /// Asks where to save a Word document and writes `data` there.
    static func exportDocx(_ data: Data, suggestedName: String) async throws -> URL? {
        try await save(data, title: "Export as Word Document", name: suggestedName + ".docx", type: UTType(filenameExtension: "docx") ?? .data)
    }

    /// Asks where to save a PDF and writes `data` there.
    static func exportPDF(_ data: Data, suggestedName: String) async throws -> URL? {
        try await save(data, title: "Export as PDF", name: suggestedName + ".pdf", type: .pdf)
    }

    private static func save(_ data: Data, title: String, name: String, type: UTType) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "Export"
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.showsTagField = false
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        try data.write(to: url, options: .atomic)
        return url
    }
}
