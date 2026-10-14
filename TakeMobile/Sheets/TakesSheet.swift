import SwiftUI
import ManuscriptKit

/// The scene's texts: main first, then each live take with its words
/// against main and its saves, then the discarded ones with Restore. A row
/// opens that text in the editor.
struct TakesSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Main", symbol: "doc.text", detail: "\(model.wordCountOnMain.formatted()) words", selected: !model.isInTake) {
                        if let scene = model.selection?.sceneID { model.select(.main(scene)) }
                        dismiss()
                    }
                    ForEach(model.takes) { take in
                        let summary = model.summary(of: take)
                        row(take.name, symbol: "arrow.triangle.branch", detail: summary, selected: model.selection == .take(take)) {
                            model.select(.take(take))
                            dismiss()
                        }
                    }
                }
                if !model.discarded.isEmpty {
                    Section("Discarded") {
                        ForEach(model.discarded) { take in
                            HStack {
                                Label(take.name, systemImage: "arrow.triangle.branch")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Restore") {
                                    model.restore(discarded: take)
                                    dismiss()
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                Section {
                    Button("New Take…", systemImage: "plus") {
                        dismiss()
                        model.naming = .take
                    }
                }
            }
            .navigationTitle(model.sceneTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, symbol: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Accent.current.color)
                }
            }
        }
        .tint(.primary)
    }
}
