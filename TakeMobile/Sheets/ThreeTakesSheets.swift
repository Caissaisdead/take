import SwiftUI

/// Asked before the first send, and every time unless the writer says not
/// to. The phone sends exactly what the Mac sends, and says so.
struct MobileConsentSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var alwaysAsk = !(UserDefaults.standard.object(forKey: ConsentGate.alwaysAskKey) as? Bool == false)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Three Takes sends the open scene, the scenes on either side of it, and the Untangle beat sheet if there is one, to Anthropic's API under your own key: exactly what the Mac sends. Anthropic's usage policy and privacy terms apply. Nothing else leaves this iPhone, and Untangle never sends anything.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Ask every time", isOn: $alwaysAsk)
                }
                Section {
                    Button("Send") {
                        ConsentGate.agree(alwaysAsk: alwaysAsk)
                        dismiss()
                        // The runs sheet comes up once this one has gone.
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            model.writeThreeTakes()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("Send this scene to Anthropic?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The three angles and how far each has got. Done opens the Takes sheet
/// when any take was written.
struct MobileThreeTakesSheet: View {
    @Environment(ProjectModel.self) private var model
    var onDone: (_ written: Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Written one after another on \(ClaudeClient.model), each told what the earlier ones did.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(model.takeRuns ?? []) { run in
                        HStack(alignment: .top, spacing: 12) {
                            icon(for: run.state)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Take \(run.angle.id): \(run.angle.name)")
                                    .fontWeight(.medium)
                                Text(run.angle.card)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(detail(for: run.state))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Three takes of “\(model.sceneTitle)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isWritingTakes ? "Stop" : "Done") {
                        let written = model.takeRuns?.contains { if case .done = $0.state { return true } else { return false } } ?? false
                        onDone(written)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.isWritingTakes)
    }

    @ViewBuilder
    private func icon(for state: ProjectModel.TakeRun.State) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .writing: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func detail(for state: ProjectModel.TakeRun.State) -> String {
        switch state {
        case .waiting: return "Waiting"
        case .writing: return "Writing…"
        case .done(let note): return note
        case .failed(let why): return why
        }
    }
}
