import SwiftUI

/// The first screen: every project on the phone, and the way to add one.
struct ProjectsView: View {
    @Environment(ProjectModel.self) private var model
    @Environment(ProjectIndex.self) private var index
    @Binding var path: [Route]
    @State private var adding = false
    @State private var removing: ProjectEntry?

    var body: some View {
        List {
            ForEach(index.entries) { entry in
                Button {
                    open(entry)
                } label: {
                    ProjectRow(entry: entry)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button("Remove", systemImage: "trash", role: .destructive) { removing = entry }
                }
            }
        }
        .overlay {
            if index.entries.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "books.vertical", description: Text("Pull a draft from a remote to begin."))
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Pull from a remote", systemImage: "icloud.and.arrow.down") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            AddProjectSheet { entry in open(entry) }
        }
        .confirmationDialog(
            "Remove “\(removing?.title ?? "")” from this iPhone?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from this iPhone", role: .destructive) {
                if let removing { remove(removing) }
            }
        } message: {
            Text("Only the copy on this iPhone goes. The remote and the Mac keep everything, takes and all.")
        }
    }

    private func open(_ entry: ProjectEntry) {
        model.open(entry.folder)
        guard model.projectURL == entry.folder else { return }
        index.note(model)
        path = [.project(entry.id)]
    }

    private func remove(_ entry: ProjectEntry) {
        if model.projectURL == entry.folder { model.close() }
        index.remove(entry)
    }
}

private struct ProjectRow: View {
    let entry: ProjectEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title.isEmpty ? "Untitled" : entry.title)
                .font(.body)
            Text("\(entry.words.formatted()) \(entry.words == 1 ? "word" : "words") · \(entry.chapters) \(entry.chapters == 1 ? "chapter" : "chapters")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let when = latest {
                Text(when)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// "backed up 3 min ago" or "pulled yesterday", whichever came last.
    private var latest: String? {
        let events = [("backed up", entry.lastBackedUp), ("pulled", entry.lastPulled)]
            .compactMap { verb, date in date.map { (verb, $0) } }
        guard let last = events.max(by: { $0.1 < $1.1 }) else { return nil }
        return "\(last.0) \(last.1.formatted(.relative(presentation: .named)))"
    }
}
