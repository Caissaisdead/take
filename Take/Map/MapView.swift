import SwiftUI
import ManuscriptKit

/// A chapter as a map with time running down the page. Each scene is a line
/// of its saves, oldest at the top and main's head at the bottom, with
/// milestones flagged on the beads they mark. A take hangs off the bead it
/// was begun from, so the beads beneath it are how far main has moved since:
/// what a Keep will have to settle. Live takes are solid, discarded ones
/// faded. A bead opens the scene compared against that save; a card opens
/// the take.
struct MapView: View {
    @Environment(ProjectModel.self) private var model
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    private var accent: Color { (Accent(rawValue: accentName) ?? .blue).color }
    /// Opens a scene in the editor compared against a save or a milestone.
    var onCompare: (SceneID, ProjectModel.CompareBase) -> Void
    @State private var columns: [ProjectModel.MapColumn] = []

    private let columnWidth: CGFloat = 450
    /// The line's x within its column; bead labels sit to its left, so no
    /// branch crosses them, and cards to its right.
    private let lineX: CGFloat = 150
    private let headerSize = CGSize(width: 420, height: 60)
    private let rowGap: CGFloat = 44
    private let cardSize = CGSize(width: 240, height: 66)
    private let cardX: CGFloat = 186
    private let inset: CGFloat = 32

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
                            drawLines(in: &context)
                        }
                        .frame(width: contentSize.width, height: contentSize.height)
                        ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                            columnViews(index: index, column: column)
                        }
                    }
                    .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                    .padding(inset)
                }
            }
        }
        .task(id: mapKey) { rebuild() }
    }

    @ViewBuilder
    private func columnViews(index: Int, column: ProjectModel.MapColumn) -> some View {
        let x = CGFloat(index) * columnWidth
        HeaderView(node: column.main, isOpen: isOpen(column.main))
            .frame(width: headerSize.width, height: headerSize.height)
            .position(x: x + headerSize.width / 2, y: headerSize.height / 2)
            .onTapGesture { model.open(column.main) }
        if column.earlier {
            Text("earlier saves not shown")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: lineX - 20, alignment: .trailing)
                .position(x: x + lineX - 12 - (lineX - 20) / 2, y: beadY(row: 0, in: column) - rowGap * 0.6)
        }
        ForEach(Array(column.beads.enumerated()), id: \.element.id) { row, bead in
            let isHead = row == column.beads.count - 1
            let y = beadY(row: row, in: column)
            BeadView(bead: bead, isHead: isHead, isOpen: isHead && isOpen(column.main), accent: accent)
                .position(x: x + lineX, y: y)
                .onTapGesture {
                    if isHead { model.open(column.main) } else { onCompare(column.scene.id, .version(bead.id)) }
                }
            BeadLabel(bead: bead, isHead: isHead, first: row == 0 && !column.earlier) { milestone in
                onCompare(column.scene.id, .milestone(milestone.id))
            }
            .frame(width: lineX - 20, alignment: .trailing)
            .position(x: x + lineX - 12 - (lineX - 20) / 2, y: y)
        }
        ForEach(placedTakes(in: column), id: \.node.id) { placed in
            TakeCard(node: placed.node, isOpen: isOpen(placed.node))
                .frame(width: cardSize.width, height: cardSize.height)
                .position(x: x + cardX + cardSize.width / 2, y: placed.y + cardSize.height / 2)
                .onTapGesture { model.open(placed.node) }
        }
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
        let saves = columns.reduce(0) { $0 + $1.beads.count }
        return "\(columns.count) scenes · \(saves) saves · \(takes) takes · a bead compares, a card opens"
    }

    private func isOpen(_ node: ProjectModel.MapNode) -> Bool {
        switch (node.kind, model.selection) {
        case (.main, .main(let id)?): return node.id == "main:\(id.uuid.uuidString)"
        case (.take(let take), .take(let open)?): return take.id == open.id
        default: return false
        }
    }

    // MARK: - Geometry

    /// Where a column's line starts: under the header, with room for the
    /// "earlier" note when the line was cut.
    private func lineTop(in column: ProjectModel.MapColumn) -> CGFloat {
        headerSize.height + (column.earlier ? rowGap : rowGap * 0.7)
    }

    private func beadY(row: Int, in column: ProjectModel.MapColumn) -> CGFloat {
        lineTop(in: column) + CGFloat(row) * rowGap
    }

    private struct PlacedTake {
        var node: ProjectModel.MapNode
        /// The card's top edge.
        var y: CGFloat
        /// The bead the take hangs from, or the line's top when that save is
        /// older than the line shows.
        var fromY: CGFloat
    }

    /// Takes in the order they were begun, each at its bead's height unless
    /// the card above reaches that far, in which case it sits just below.
    private func placedTakes(in column: ProjectModel.MapColumn) -> [PlacedTake] {
        let sorted = column.takes.sorted { ($0.baseRow ?? -1, $0.title) < ($1.baseRow ?? -1, $1.title) }
        var placed: [PlacedTake] = []
        var next = lineTop(in: column) - cardSize.height / 2
        for take in sorted {
            let fromY = take.baseRow.map { beadY(row: $0, in: column) } ?? lineTop(in: column) - rowGap * 0.5
            let y = max(fromY - cardSize.height / 2, next)
            placed.append(PlacedTake(node: take, y: y, fromY: fromY))
            next = y + cardSize.height + 10
        }
        return placed
    }

    private func columnHeight(_ column: ProjectModel.MapColumn) -> CGFloat {
        let lineBottom = beadY(row: max(column.beads.count - 1, 0), in: column) + rowGap * 0.5
        let cardsBottom = placedTakes(in: column).last.map { $0.y + cardSize.height } ?? 0
        return max(lineBottom, cardsBottom)
    }

    private var contentSize: CGSize {
        CGSize(
            width: CGFloat(max(columns.count, 1)) * columnWidth,
            height: (columns.map(columnHeight).max() ?? 0) + 8)
    }

    private func drawLines(in context: inout GraphicsContext) {
        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * columnWidth + lineX
            guard !column.beads.isEmpty else { continue }
            // The line, from the first save shown to main's head, with a
            // fade upward when older saves exist.
            var line = Path()
            line.move(to: CGPoint(x: x, y: beadY(row: 0, in: column) - (column.earlier ? rowGap * 0.6 : 0)))
            line.addLine(to: CGPoint(x: x, y: beadY(row: column.beads.count - 1, in: column)))
            context.stroke(line, with: .color(.secondary.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: column.earlier ? [] : []))
            // Each take's branch: from its bead out to its card.
            for placed in placedTakes(in: column) {
                let start = CGPoint(x: x, y: placed.fromY)
                let end = CGPoint(x: CGFloat(index) * columnWidth + cardX, y: placed.y + cardSize.height / 2)
                var branch = Path()
                branch.move(to: start)
                branch.addCurve(to: end,
                                control1: CGPoint(x: start.x + 60, y: start.y),
                                control2: CGPoint(x: end.x - 60, y: end.y))
                let faded: Bool
                if case .discarded = placed.node.kind { faded = true } else { faded = false }
                context.stroke(branch, with: .color(faded ? .secondary.opacity(0.35) : accent),
                               style: StrokeStyle(lineWidth: 1.5, dash: faded ? [3, 3] : []))
                if placed.node.baseRow != nil {
                    let dot = Path(ellipseIn: CGRect(x: start.x - 3.5, y: start.y - 3.5, width: 7, height: 7))
                    context.fill(dot, with: .color(faded ? .secondary.opacity(0.5) : accent))
                }
            }
        }
    }
}

/// The scene at the head of its column: title, words, synopsis.
private struct HeaderView: View {
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    private var accent: Color { (Accent(rawValue: accentName) ?? .blue).color }
    let node: ProjectModel.MapNode
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                Text(node.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(node.words) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(node.synopsis.isEmpty ? "No synopsis" : node.synopsis)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? accent : Color.secondary.opacity(0.3), lineWidth: isOpen ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help("Main. Click to open the scene.")
    }
}

/// One save on the line: hollow for a checkpoint, filled in the accent for a
/// keep, ringed when it is the head of the open scene.
private struct BeadView: View {
    let bead: ProjectModel.MapBead
    let isHead: Bool
    let isOpen: Bool
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(bead.isKeep ? accent : Color(nsColor: .controlBackgroundColor))
                .frame(width: isHead ? 14 : 11, height: isHead ? 14 : 11)
            Circle()
                .strokeBorder(isOpen ? accent : Color.primary.opacity(0.7), lineWidth: isHead ? 2.5 : 2)
                .frame(width: isHead ? 14 : 11, height: isHead ? 14 : 11)
        }
        .frame(width: 24, height: 24)
        .contentShape(Circle())
        .help(isHead ? "Main now. Click to open the scene." : "\(bead.message) · \(bead.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())). Click to compare the scene against it.")
    }
}

/// What a bead is: a milestone's flag and name when one marks it, else the
/// save's date, with "begun" on the first and "now" on the head.
private struct BeadLabel: View {
    let bead: ProjectModel.MapBead
    let isHead: Bool
    let first: Bool
    let onMilestone: (Milestone) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let milestone = bead.milestones.first {
                Button {
                    onMilestone(milestone)
                } label: {
                    HStack(spacing: 4) {
                        if isHead {
                            Text("now ·")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        Label(bead.milestones.count == 1 ? milestone.name : "\(milestone.name) +\(bead.milestones.count - 1)", systemImage: "flag.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Milestone. Click to compare the scene against it.")
            } else {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(isHead ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private var text: String {
        let day = bead.date.formatted(.dateTime.month(.abbreviated).day())
        if isHead { return "now · \(day)" }
        if first { return "begun · \(day)" }
        if bead.isKeep { return "keep · \(day)" }
        return day
    }
}

/// A take: its name, its words against main, and how far main has moved
/// since it was begun, which is what a Keep will have to settle.
private struct TakeCard: View {
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    private var accent: Color { (Accent(rawValue: accentName) ?? .blue).color }
    let node: ProjectModel.MapNode
    let isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(faded ? Color.secondary : accent)
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
        .background(faded ? Color(nsColor: .controlBackgroundColor) : accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? accent : Color.secondary.opacity(0.3), lineWidth: isOpen ? 2 : 1))
        .opacity(faded ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .help(faded ? "A discarded take. Click to bring it back." : "A live take. Click to open it.")
    }

    private var faded: Bool {
        if case .discarded = node.kind { return true }
        return false
    }

    private var detail: String {
        var parts: [String] = []
        if let delta = node.delta {
            parts.append(delta.added == 0 && delta.removed == 0 ? "same as main" : "+\(delta.added) −\(delta.removed)")
        }
        parts.append(node.saves == 1 ? "1 save" : "\(node.saves) saves")
        if faded {
            parts.append("discarded")
        } else if node.mainSavesSince == 0 {
            parts.append("main unchanged since")
        } else {
            parts.append(node.mainSavesSince == 1 ? "main moved 1 save since" : "main moved \(node.mainSavesSince) saves since")
        }
        return parts.joined(separator: " · ")
    }
}
