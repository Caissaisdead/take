import SwiftUI
import ManuscriptKit

/// The draft since a milestone: every scene with the words it gained and
/// lost, grouped by chapter, the scenes gone since at the end. A click opens
/// the scene compared against that milestone.
struct ChangesView: View {
    @Environment(ProjectModel.self) private var model
    /// Opens a scene in the editor, compared against the milestone's ref.
    var onOpen: (SceneID, Milestone) -> Void
    @State private var chosen: String?
    @State private var changes: [SceneChange] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Since", selection: $chosen) {
                    ForEach(model.milestones) { milestone in
                        Text("\(milestone.name) · \(milestone.date, format: .dateTime.month(.abbreviated).day())").tag(Optional(milestone.id))
                    }
                }
                .frame(maxWidth: 360)
                Spacer()
                Text(legend)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if model.milestones.isEmpty {
                ContentUnavailableView("No milestone yet", systemImage: "flag", description: Text("Mark one with ⇧⌘M, and this shows what moved since."))
            } else if let milestone {
                List {
                    ForEach(groups, id: \.chapter) { group in
                        Section(group.title) {
                            ForEach(group.changes) { change in
                                ChangeRow(change: change, scale: scale)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if change.kind != .removed { onOpen(change.scene.id, milestone) }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { if chosen == nil { chosen = model.milestones.first?.id }; rebuild() }
        .onChange(of: chosen) { rebuild() }
        .onChange(of: model.mapVersion) {
            if chosen == nil || !model.milestones.contains(where: { $0.id == chosen }) { chosen = model.milestones.first?.id }
            rebuild()
        }
    }

    private var milestone: Milestone? {
        model.milestones.first { $0.id == chosen }
    }

    private func rebuild() {
        guard let milestone else { changes = []; return }
        changes = model.changes(since: milestone)
    }

    private var legend: String {
        let added = changes.reduce(0) { $0 + $1.wordsAdded }
        let removed = changes.reduce(0) { $0 + $1.wordsRemoved }
        let moved = changes.filter { $0.kind != .same }.count
        return "\(moved) of \(changes.count) scenes moved · +\(added.formatted()) −\(removed.formatted()) words"
    }

    /// The bars are drawn against the busiest scene.
    private var scale: Int {
        max(changes.map { max($0.wordsAdded, $0.wordsRemoved) }.max() ?? 1, 1)
    }

    private struct Group {
        var chapter: String
        var title: String
        var changes: [SceneChange]
    }

    private var groups: [Group] {
        var groups: [Group] = []
        for change in changes {
            let key = change.kind == .removed ? "removed" : change.chapter.uuidString
            let title = change.kind == .removed ? "Gone since" : (model.manuscript.chapter(change.chapter)?.title ?? "Untitled Chapter")
            if let last = groups.indices.last, groups[last].chapter == key {
                groups[last].changes.append(change)
            } else {
                groups.append(Group(chapter: key, title: title.isEmpty ? "Untitled Chapter" : title, changes: [change]))
            }
        }
        return groups
    }
}

private struct ChangeRow: View {
    let change: SceneChange
    let scale: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(change.scene.title)
                .lineLimit(1)
                .foregroundStyle(change.kind == .removed ? .secondary : .primary)
            Spacer()
            Text(counts)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            bar
                .frame(width: 160, height: 6)
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch change.kind {
        case .added: return "plus.circle"
        case .removed: return "minus.circle"
        case .changed: return "pencil.circle"
        case .same: return "circle"
        }
    }

    private var tint: Color {
        switch change.kind {
        case .added: return .green
        case .removed: return .red
        case .changed: return .accentColor
        case .same: return .secondary
        }
    }

    private var counts: String {
        switch change.kind {
        case .same: return "unchanged"
        case .added: return "new, \(change.wordsAdded.formatted()) words"
        case .removed: return "−\(change.wordsRemoved.formatted()) words"
        case .changed: return "+\(change.wordsAdded.formatted()) −\(change.wordsRemoved.formatted())"
        }
    }

    /// Green to the right for what came, red to the left for what went.
    private var bar: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            let added = half * CGFloat(change.wordsAdded) / CGFloat(scale)
            let removed = half * CGFloat(change.wordsRemoved) / CGFloat(scale)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Rectangle().fill(.red.opacity(0.7)).frame(width: removed).offset(x: half - removed)
                Rectangle().fill(.green.opacity(0.7)).frame(width: added).offset(x: half)
            }
        }
    }
}
