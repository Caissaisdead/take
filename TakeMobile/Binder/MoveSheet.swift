import SwiftUI
import ManuscriptKit

/// Where a scene goes: the chapter list, since the phone does not drag.
struct MoveSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scene: SceneRef

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.manuscript.parts) { part in
                    Section {
                        ForEach(part.chapters) { chapter in
                            Button {
                                model.move(scene: scene.id, toChapter: chapter.id, at: chapter.scenes.count)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(chapter.title.isEmpty ? "Untitled Chapter" : chapter.title)
                                    Spacer()
                                    if chapter.scenes.contains(where: { $0.id == scene.id }) {
                                        Text("Here now").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        if model.manuscript.usesParts { Text(part.title.isEmpty ? "Untitled Part" : part.title) }
                    }
                }
            }
            .navigationTitle("Move “\(scene.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
