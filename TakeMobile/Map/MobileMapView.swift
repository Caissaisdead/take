import SwiftUI
import ManuscriptKit

/// The Mac's map is wide; the phone's is tall. Each scene is a card with its
/// words and synopsis, its takes indented beneath, live ones tinted and
/// discarded ones faded and dashed. A card opens the text.
struct MobileMapView: View {
    @Environment(ProjectModel.self) private var model
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    @Binding var path: [Route]
    @State private var columns: [ProjectModel.MapColumn] = []

    private var accent: Color { (Accent(rawValue: accentName) ?? .blue).color }

    var body: some View {
        List {
            ForEach(columns) { column in
                Section {
                    Button { open(column.main) } label: { mainCard(column) }
                        .buttonStyle(.plain)
                    ForEach(column.takes) { node in
                        Button { open(node) } label: { takeCard(node) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 36, bottom: 4, trailing: 16))
                    }
                }
            }
            if columns.isEmpty {
                ContentUnavailableView("No chapter", systemImage: "map", description: Text("Add a scene and the map shows its saves and takes."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(chapterTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            ForEach(model.manuscript.chapters) { chapter in
                Button {
                    model.mapChapter = chapter.id
                } label: {
                    if chapter.id == model.mapChapterID {
                        Label(chapter.title.isEmpty ? "Untitled Chapter" : chapter.title, systemImage: "checkmark")
                    } else {
                        Text(chapter.title.isEmpty ? "Untitled Chapter" : chapter.title)
                    }
                }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: model.mapChapterID) { rebuild() }
        .onChange(of: model.mapVersion) { rebuild() }
    }

    private var chapterTitle: String {
        let title = model.mapChapterID.flatMap { model.manuscript.chapter($0)?.title } ?? ""
        return "Map · " + (title.isEmpty ? "Untitled Chapter" : title)
    }

    private func rebuild() {
        guard let chapter = model.mapChapterID else { columns = []; return }
        columns = model.chapterMap(chapter)
    }

    private func open(_ node: ProjectModel.MapNode) {
        model.open(node)
        guard let scene = model.selection?.sceneID else { return }
        if case .discarded = node.kind { return }
        path = Array(path.prefix(1)) + [.scene(scene)]
    }

    private func mainCard(_ column: ProjectModel.MapColumn) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
                Text(column.scene.title.isEmpty ? "Untitled Scene" : column.scene.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(column.main.words.formatted()) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if !column.scene.synopsis.isEmpty {
                Text(column.scene.synopsis)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(saves(column))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// "4 saves · milestone First draft"
    private func saves(_ column: ProjectModel.MapColumn) -> String {
        var parts = [ProjectModel.count(column.beads.count, "save") + (column.earlier ? " shown" : "")]
        let flagged = column.beads.flatMap(\.milestones).map(\.name)
        if !flagged.isEmpty { parts.append("milestone " + flagged.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func takeCard(_ node: ProjectModel.MapNode) -> some View {
        let faded: Bool = { if case .discarded = node.kind { return true }; return false }()
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(faded ? Color.secondary : accent)
                Text(node.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(detail(node, faded: faded))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(faded ? Color.clear : accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: faded ? [4, 3] : []))
                .foregroundStyle(faded ? Color.secondary.opacity(0.5) : accent.opacity(0.4))
        )
        .opacity(faded ? 0.6 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func detail(_ node: ProjectModel.MapNode, faded: Bool) -> String {
        var parts: [String] = []
        if let delta = node.delta {
            parts.append(delta.added == 0 && delta.removed == 0 ? "same as main" : "+\(delta.added) −\(delta.removed) vs main")
        }
        parts.append(ProjectModel.count(node.saves, "save"))
        if faded {
            parts.append("discarded; tap to bring back")
        } else if node.mainSavesSince == 0 {
            parts.append("main unchanged since")
        } else {
            parts.append("main moved \(ProjectModel.count(node.mainSavesSince, "save")) since")
        }
        return parts.joined(separator: " · ")
    }
}
