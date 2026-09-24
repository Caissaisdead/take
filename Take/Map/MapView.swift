import SwiftUI
import ManuscriptKit

/// A chapter as a map: its scenes in a line, left to right, with every take of
/// a scene as a node beneath it, live takes solid and discarded ones faded.
/// Clicking a node opens it in the editor.
struct MapView: View {
    @Environment(ProjectModel.self) private var model
    @State private var columns: [ProjectModel.MapColumn] = []

    private let columnWidth: CGFloat = 270
    private let nodeSize = CGSize(width: 210, height: 84)
    private let top: CGFloat = 36
    private let takeGap: CGFloat = 108
    private let inset: CGFloat = 32
    /// Takes sit this far right of their scene, beside the spine that joins them.
    private let takeIndent: CGFloat = 28

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                Picker("Chapter", selection: chapterBinding) {
                    ForEach(model.manuscript.chapters) { chapter in
                        Text(chapter.title.isEmpty ? "Untitled Chapter" : chapter.title).tag(Optional(chapter.id))
                    }
                }
                .frame(maxWidth: 320)
                Spacer()
                Text(legend)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if columns.isEmpty {
                ContentUnavailableView("Nothing to map", systemImage: "map", description: Text("Pick a chapter with scenes in it."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            drawEdges(in: &context)
                        }
                        .frame(width: contentSize.width, height: contentSize.height)
                        ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                            NodeView(node: column.main, isOpen: isOpen(column.main))
                                .frame(width: nodeSize.width, height: nodeSize.height)
                                .position(center(column: index, row: 0))
                                .onTapGesture { model.open(column.main) }
                            ForEach(Array(column.takes.enumerated()), id: \.element.id) { row, take in
                                NodeView(node: take, isOpen: isOpen(take))
                                    .frame(width: nodeSize.width, height: nodeSize.height)
                                    .position(center(column: index, row: row + 1))
                                    .onTapGesture { model.open(take) }
                            }
                        }
                    }
                    .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                    .padding(inset)
                }
            }
        }
        .task(id: mapKey) { rebuild() }
    }

    private var mapKey: String {
        "\(model.mapChapterID?.uuidString ?? "")|\(model.mapVersion)"
    }

    private func rebuild() {
        guard let chapter = model.mapChapterID else { columns = []; return }
        columns = model.chapterMap(chapter)
    }

    private var chapterBinding: Binding<UUID?> {
        Binding(get: { model.mapChapterID }, set: { model.mapChapter = $0 })
    }

    private var legend: String {
        let takes = columns.reduce(0) { $0 + $1.takes.count }
        return "\(columns.count) scenes · \(takes) takes · click a node to open it"
    }

    private func isOpen(_ node: ProjectModel.MapNode) -> Bool {
        switch (node.kind, model.selection) {
        case (.main, .main(let id)?): return node.id == "main:\(id.uuid.uuidString)"
        case (.take(let take), .take(let open)?): return take.id == open.id
        default: return false
        }
    }

    // MARK: - Geometry

    private var contentSize: CGSize {
        let rows = (columns.map { $0.takes.count }.max() ?? 0) + 1
        return CGSize(
            width: CGFloat(max(columns.count, 1)) * columnWidth,
            height: top + CGFloat(rows) * takeGap + nodeSize.height)
    }

    private func center(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: CGFloat(column) * columnWidth + 20 + nodeSize.width / 2 + (row == 0 ? 0 : takeIndent),
            y: top + nodeSize.height / 2 + CGFloat(row) * takeGap)
    }

    /// The x of the spine that drops from a scene to its takes.
    private func spineX(column: Int) -> CGFloat {
        CGFloat(column) * columnWidth + 20 + 12
    }

    private func drawEdges(in context: inout GraphicsContext) {
        // The main line: scene to scene, left to right.
        for index in columns.indices.dropLast() {
            let from = center(column: index, row: 0)
            let to = center(column: index + 1, row: 0)
            var line = Path()
            line.move(to: CGPoint(x: from.x + nodeSize.width / 2, y: from.y))
            line.addLine(to: CGPoint(x: to.x - nodeSize.width / 2, y: to.y))
            context.stroke(line, with: .color(.secondary), style: StrokeStyle(lineWidth: 2))
            var head = Path()
            let tip = CGPoint(x: to.x - nodeSize.width / 2, y: to.y)
            head.move(to: tip)
            head.addLine(to: CGPoint(x: tip.x - 8, y: tip.y - 5))
            head.addLine(to: CGPoint(x: tip.x - 8, y: tip.y + 5))
            head.closeSubpath()
            context.fill(head, with: .color(.secondary))
        }
        // A spine drops from each scene past its takes; a stub reaches each take.
        for (index, column) in columns.enumerated() where !column.takes.isEmpty {
            let x = spineX(column: index)
            let sceneBottom = center(column: index, row: 0).y + nodeSize.height / 2
            let lastY = center(column: index, row: column.takes.count).y
            var spine = Path()
            spine.move(to: CGPoint(x: x, y: sceneBottom))
            spine.addLine(to: CGPoint(x: x, y: lastY))
            context.stroke(spine, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5))
            for (row, take) in column.takes.enumerated() {
                let to = center(column: index, row: row + 1)
                var stub = Path()
                stub.move(to: CGPoint(x: x, y: to.y))
                stub.addLine(to: CGPoint(x: to.x - nodeSize.width / 2, y: to.y))
                let faded: Bool
                if case .discarded = take.kind { faded = true } else { faded = false }
                context.stroke(stub, with: .color(faded ? .secondary.opacity(0.35) : .accentColor),
                               style: StrokeStyle(lineWidth: 1.5, dash: faded ? [3, 3] : []))
                let dot = Path(ellipseIn: CGRect(x: x - 3.5, y: to.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(faded ? .secondary.opacity(0.5) : .accentColor))
            }
        }
    }
}

private struct NodeView: View {
    let node: ProjectModel.MapNode
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(node.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isOpen ? 2 : 1))
        .opacity(faded ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(help)
    }

    private var faded: Bool {
        if case .discarded = node.kind { return true }
        return false
    }

    private var icon: String {
        switch node.kind {
        case .main: return "doc.text"
        case .take: return "arrow.triangle.branch"
        case .discarded: return "arrow.triangle.branch"
        }
    }

    private var tint: Color {
        switch node.kind {
        case .main: return .primary
        case .take: return .accentColor
        case .discarded: return .secondary
        }
    }

    private var background: Color {
        switch node.kind {
        case .main: return Color(nsColor: .controlBackgroundColor)
        case .take: return Color.accentColor.opacity(0.08)
        case .discarded: return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var detail: String {
        var parts = ["\(node.words) words"]
        if let delta = node.delta {
            parts.append(delta.added == 0 && delta.removed == 0 ? "same as main" : "+\(delta.added) −\(delta.removed) vs main")
        }
        switch node.kind {
        case .main: break
        case .take: parts.append(node.saves == 1 ? "1 save" : "\(node.saves) saves")
        case .discarded: parts.append("discarded")
        }
        return parts.joined(separator: " · ")
    }

    private var help: String {
        switch node.kind {
        case .main: return "Main. Click to open the scene."
        case .take: return "A live take. Click to open it."
        case .discarded: return "A discarded take. Click to bring it back."
        }
    }
}
