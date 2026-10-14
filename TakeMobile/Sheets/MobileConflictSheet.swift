import SwiftUI

/// Main changed since the take began, so Keep could not merge on its own.
/// One text at a time on the phone, a picker to turn between the three, and
/// a choice of whole scene; nothing is written until the writer chooses.
struct MobileConflictSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let conflict: ProjectModel.Conflict
    @State private var showing = Side.take

    private enum Side: String, CaseIterable, Identifiable {
        case base = "Where both began"
        case main = "Main now"
        case take = "The take"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing has been written. Keep one whole scene; the other stays in history either way.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Picker("Text", selection: $showing) {
                    ForEach(Side.allCases) { side in Text(side.rawValue).tag(side) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                ScrollView {
                    Text(text)
                        .font(.system(size: 17, design: .serif))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                HStack {
                    Button("Keep Main’s") { model.settle(conflict, choosing: .main) }
                        .buttonStyle(.bordered)
                    Button("Keep the Take’s") { model.settle(conflict, choosing: .take) }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Main changed since “\(conflict.take.name)” began")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Decide Later") { dismiss() } }
            }
        }
    }

    private var text: String {
        switch showing {
        case .base: return conflict.base
        case .main: return conflict.main
        case .take: return conflict.text
        }
    }
}
