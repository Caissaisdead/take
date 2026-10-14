import SwiftUI
import ManuscriptKit

/// Compare, over the page: a picker for the other side, the summary, then
/// the diff paragraph by paragraph with a button under each change. At the
/// medium detent the page stays readable above it.
struct MobileCompareSheet: View {
    @Environment(ProjectModel.self) private var model
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    @State private var diff: ProseDiff?

    var body: some View {
        @Bindable var model = model
        SheetHost(title: "Compare") {
            VStack(spacing: 0) {
                HStack {
                    Picker("Against", selection: $model.compareBase) {
                        ForEach(model.compareChoices, id: \.base) { choice in
                            Text(choice.label).tag(choice.base)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding(.horizontal, 12)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                Divider()
                if let diff {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(diff.segments.enumerated()), id: \.offset) { index, segment in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(Self.text(for: segment))
                                        .font(.system(size: 17, design: .serif))
                                        .lineSpacing(5)
                                        .textSelection(.enabled)
                                    if let verb = Self.verb(for: segment) {
                                        Button(verb) { model.pick(segment: index) }
                                            .font(.caption)
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .tint(Accent(rawValue: accentName)?.color ?? .blue)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView("Nothing to compare", systemImage: "doc.on.doc", description: Text("Pick a version or milestone above. Main compares with its previous version once it has one."))
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model.compareBase) { refresh() }
        .onChange(of: model.loadToken) { refresh() }
        .onChange(of: model.editCount) { refresh() }
    }

    private func refresh() {
        diff = model.compare()
    }

    private var summary: String {
        guard let diff else { return "No comparison" }
        let s = diff.summary
        return "\(s.paragraphsChanged) \(s.paragraphsChanged == 1 ? "paragraph" : "paragraphs") changed  +\(s.wordsAdded) −\(s.wordsRemoved) words"
    }

    private static func verb(for segment: ProseDiff.Segment) -> String? {
        switch segment {
        case .equal: return nil
        case .removed: return "Bring back"
        case .inserted: return "Drop"
        case .changed: return "Take theirs"
        }
    }

    /// The paragraph styled as the Mac draws it: red struck for removed,
    /// green underlined for added, the unchanged dimmed.
    private static func text(for segment: ProseDiff.Segment) -> AttributedString {
        switch segment {
        case .equal(let paragraph):
            return run(paragraph, color: .secondary)
        case .removed(let paragraph):
            return run(paragraph, color: .red, strike: true)
        case .inserted(let paragraph):
            return run(paragraph, color: .green, underline: true)
        case .changed(_, _, let words):
            var out = AttributedString()
            for word in words {
                switch word {
                case .equal(let token): out += run(token, color: .primary)
                case .removed(let token): out += run(token, color: .red, strike: true)
                case .inserted(let token): out += run(token, color: .green, underline: true)
                }
            }
            return out
        }
    }

    private static func run(_ token: String, color: Color, strike: Bool = false, underline: Bool = false) -> AttributedString {
        var out = AttributedString(token)
        out.foregroundColor = color
        // Decoration stops before a token's trailing space, as on the Mac.
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = out.range(of: trimmed), !trimmed.isEmpty {
            if strike { out[range].strikethroughStyle = .single }
            if underline { out[range].underlineStyle = .single }
        }
        return out
    }
}
