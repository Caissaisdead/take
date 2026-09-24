import AppKit
import UniformTypeIdentifiers

/// The open and save panels for projects. The sandbox grants the app the
/// folder that comes back, and a bookmark keeps the grant across launches.
@MainActor
enum ProjectPanels {
    /// A folder holding a project, or an empty one to start a project in.
    static func chooseProjectFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.message = "Choose a project folder. An empty folder becomes a new project."
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }

    /// Where to make a new project; the folder's name is the project's title.
    static func chooseNewProjectFolder(named name: String = "Untitled Manuscript", message: String? = nil) async -> URL? {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.message = message ?? "The folder becomes a git repository with one file per scene."
        panel.prompt = "Create"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.showsTagField = false
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }

    /// A manuscript to import: a Markdown, text or Word file, or a folder of
    /// Markdown files.
    static func chooseImport() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Manuscript"
        panel.message = "A Markdown, text or Word file, or a folder of Markdown files with one file per scene. Headings become chapters and scenes."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .folder, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText, UTType(filenameExtension: "docx") ?? .data]
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}
