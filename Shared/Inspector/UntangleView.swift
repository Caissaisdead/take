import SwiftUI

/// The Untangle pane: the template, filled for the open scene. Nothing here
/// writes into the draft.
struct UntangleView: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button {
                        model.untangle()
                    } label: {
                        Label(model.untangling == nil ? "Untangle This Scene" : "Untangle Again", systemImage: "wand.and.sparkles")
                    }
                    .disabled(model.selection == nil || model.isUntangling)
                    if model.isUntangling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                Text("On this Mac, on Apple's model. Nothing is written into the draft.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = model.untangleError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if let result = model.untangling {
                    if let note = result.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    section("What the scene is for", result.job)
                    section("The shift", result.shift)
                    list("Beats", result.beats, numbered: true)
                    section("The reader must", result.reader)
                    if !result.questions.isEmpty {
                        list("Only you can answer", result.questions, numbered: false)
                    }
                    section("The smallest version", result.sketch)
                        .textSelection(.enabled)
                } else if let reason = model.untangleUnavailable {
                    ContentUnavailableView("Not available", systemImage: "wand.and.sparkles", description: Text(reason))
                } else if !model.isUntangling {
                    Text("A one-line job, the value shift, the beats, what the reader needs, and the smallest version of the scene.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(body)
                .font(.callout)
        }
    }

    private func list(_ title: String, _ items: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(numbered ? "\(index + 1)." : "•")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(item)
                        .font(.callout)
                }
            }
        }
    }
}
