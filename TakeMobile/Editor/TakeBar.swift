import SwiftUI

/// The two things a take exists for, one tap away while it is open.
struct TakeBar: View {
    @Environment(ProjectModel.self) private var model
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: 12) {
            Button("Keep", systemImage: "checkmark.circle") { model.keep() }
                .buttonStyle(.borderedProminent)
            Button("Discard", systemImage: "xmark.circle") { confirmingDiscard = true }
                .buttonStyle(.bordered)
            Spacer()
            Text(model.selectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .confirmationDialog("Discard this take?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.discard() }
        } message: {
            Text("It moves to Discarded, where it can be brought back; main is left as it is.")
        }
    }
}
