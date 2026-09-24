import SwiftUI
import ManuscriptKit

/// The scene's takes and history, in the inspector. A take selects; a version
/// restores into the editor.
struct VersionsView: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        if model.selection == nil {
            ContentUnavailableView("No scene", systemImage: "doc.text", description: Text("Select a scene to see its takes and history."))
        } else {
            List(selection: takeBinding) {
                Section("Takes") {
                    Label("Main", systemImage: "doc.text")
                        .tag(TakeRow.main)
                    ForEach(model.takes) { take in
                        Label(take.title, systemImage: "arrow.triangle.branch")
                            .tag(TakeRow.take(take))
                    }
                    if model.takes.isEmpty {
                        Text("No takes yet")
                            .foregroundStyle(.tertiary)
                            .italic()
                            .selectionDisabled()
                    }
                }
                Section("History") {
                    ForEach(model.history) { version in
                        VersionRow(version: version)
                            .selectionDisabled()
                    }
                    if model.history.isEmpty {
                        Text("Nothing saved yet")
                            .foregroundStyle(.tertiary)
                            .italic()
                            .selectionDisabled()
                    }
                }
            }
        }
    }

    private enum TakeRow: Hashable {
        case main
        case take(Take)
    }

    private var takeBinding: Binding<TakeRow?> {
        Binding(
            get: {
                switch model.selection {
                case .main: return .main
                case .take(let take): return .take(take)
                case nil: return nil
                }
            },
            set: { row in
                guard let row, let scene = model.selection?.sceneID else { return }
                switch row {
                case .main:
                    if model.isInTake { model.select(.main(scene)) }
                case .take(let take):
                    if model.selection != .take(take) { model.select(.take(take)) }
                }
            }
        )
    }
}

private struct VersionRow: View {
    @Environment(ProjectModel.self) private var model
    let version: Version

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(version.message)
                    .lineLimit(1)
                Text(version.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Restore") { model.restore(version: version) }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Load this version into the editor, unsaved")
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch version.kind {
        case .checkpoint: return "circle.fill"
        case .milestone: return "flag.fill"
        case .keep: return "arrow.triangle.merge"
        }
    }
}
