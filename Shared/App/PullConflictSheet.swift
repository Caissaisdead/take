import SwiftUI
import ManuscriptKit

/// Both sides moved since they last agreed. One answer: this side's text
/// lives on as takes and main becomes the remote's. Nothing is lost, and the
/// sheet says where everything goes before anything moves.
struct PullConflictSheet: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        let divergence = model.pullDivergence
        VStack(alignment: .leading, spacing: 12) {
            Text("The remote and this \(Platform.deviceName) both changed since they last agreed")
                .font(.headline)
            Text("Take never merges prose on its own. Main becomes the remote's, and what this \(Platform.deviceName) wrote stays as takes, where takes go, for you to compare and keep. Scene notes, synopses and order follow the remote.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let divergence {
                if !divergence.changed.isEmpty {
                    list("Kept as a take named “\(Platform.deviceName) \(Date().formatted(.dateTime.day().month(.abbreviated).year().hour().minute()))”", divergence.changed)
                }
                if !divergence.added.isEmpty {
                    list("Put back on main, since the remote never had them", divergence.added)
                }
            }
            HStack {
                Spacer()
                Button("Decide Later") { model.decidePullLater() }
                    .keyboardShortcut(.cancelAction)
                Button("Keep Mine as Takes") { model.keepMineAsTakes() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 460)
        #endif
    }

    private func list(_ heading: String, _ scenes: [SceneRef]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.subheadline.weight(.medium))
            ForEach(scenes) { scene in
                Label(scene.title, systemImage: "doc.text")
                    .font(.callout)
            }
        }
    }
}
