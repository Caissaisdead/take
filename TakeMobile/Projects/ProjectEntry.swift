import Foundation

/// One project on the phone: a clone under the container, named by its id.
struct ProjectEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var lastPulled: Date?
    var lastBackedUp: Date?
    /// For the row; refreshed whenever the project is open.
    var words = 0
    var chapters = 0

    var folder: URL {
        ProjectModel.projectsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// The remote it came from or backs up to, as the model keeps it.
    var remote: String {
        ProjectModel.readRemote(for: folder)
    }
}
