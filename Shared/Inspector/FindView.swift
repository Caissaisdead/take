import SwiftUI
import ManuscriptKit

/// The Find pane: a phrase, every place it occurs in the draft, grouped by
/// chapter and scene, and a click to go there. Runs again as the draft
/// changes, a quarter second after the last keystroke in the field.
struct FindView: View {
    @Environment(ProjectModel.self) private var model
    @State private var query = ""
    @State private var includeTakes = false
    @State private var results: [Match] = []
    @State private var pending: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Find in the draft", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(run)
                HStack {
                    Toggle("Takes too", isOn: $includeTakes)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    Spacer()
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            Divider()
            if results.isEmpty {
                ContentUnavailableView(
                    query.trimmingCharacters(in: .whitespaces).isEmpty ? "Find" : "Nothing found",
                    systemImage: "magnifyingglass",
                    description: Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Case and accents do not matter." : "Not in the draft\(includeTakes ? " or its takes" : ""). ")
                )
            } else {
                List {
                    ForEach(groups, id: \.chapter) { group in
                        Section(group.title) {
                            ForEach(group.matches) { match in
                                MatchRow(match: match, sceneTitle: model.manuscript.scene(match.scene)?.title ?? "")
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.reveal(match) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: query) { schedule() }
        .onChange(of: includeTakes) { run() }
        .onChange(of: model.mapVersion) { run() }
        .onReceive(NotificationCenter.default.publisher(for: .showFind)) { _ in fieldFocused = true }
        .onAppear { fieldFocused = true }
    }

    private var summary: String {
        guard !results.isEmpty else { return "" }
        let scenes = Set(results.map { "\($0.scene.uuid)\($0.take?.id ?? "")" }).count
        return "\(results.count) in \(scenes) \(scenes == 1 ? "place" : "places")"
    }

    private struct Group {
        var chapter: UUID
        var title: String
        var matches: [Match]
    }

    /// Results are already in manuscript order; this only cuts them at chapter lines.
    private var groups: [Group] {
        var groups: [Group] = []
        for match in results {
            guard let chapter = model.manuscript.chapter(containing: match.scene) else { continue }
            if let last = groups.indices.last, groups[last].chapter == chapter.id {
                groups[last].matches.append(match)
            } else {
                groups.append(Group(chapter: chapter.id, title: chapter.title.isEmpty ? "Untitled Chapter" : chapter.title, matches: [match]))
            }
        }
        return groups
    }

    private func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            run()
        }
    }

    private func run() {
        results = model.search(query, includingTakes: includeTakes)
    }
}

/// One hit: where, then the paragraph around it with the hit in bold, cut
/// to a window either side so a long paragraph stays one row.
private struct MatchRow: View {
    let match: Match
    let sceneTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(sceneTitle)
                if let take = match.take {
                    Text("· \(take.name)")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("¶\(match.paragraph + 1)")
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .font(.caption)
            context
                .font(.callout)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private var context: Text {
        let text = match.text
        let utf16 = text.utf16
        guard let start = utf16.index(utf16.startIndex, offsetBy: match.location, limitedBy: utf16.endIndex),
              let end = utf16.index(start, offsetBy: match.length, limitedBy: utf16.endIndex),
              let lower = String.Index(start, within: text), let upper = String.Index(end, within: text) else {
            return Text(text)
        }
        var before = String(text[..<lower])
        var after = String(text[upper...])
        if before.count > 60 { before = "…" + String(before.suffix(60)) }
        if after.count > 100 { after = String(after.prefix(100)) + "…" }
        return Text("\(before)\(Text(text[lower..<upper]).bold())\(after)")
    }
}
