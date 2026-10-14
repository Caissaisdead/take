import SwiftUI

/// A pane from the Mac's inspector, pulled up over the page: a title, a
/// Done button and the pane as it is.
struct SheetHost<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var detents: Set<PresentationDetent> = [.medium, .large]
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDetents(detents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
