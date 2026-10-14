import SwiftUI
import ManuscriptKit

/// Find, over the binder: a tap on a hit opens the editor on that scene with
/// the hit selected and puts the sheet away.
struct FindSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [Route]

    var body: some View {
        SheetHost(title: "Find", detents: [.large]) {
            FindView(onReveal: reveal)
        }
    }

    private func reveal(_ match: Match) {
        let target: ProjectModel.Selection = match.take.map { .take($0) } ?? .main(match.scene)
        model.select(target, selecting: (match.paragraph, match.location, match.length))
        guard model.selection == target else { return }
        dismiss()
        path = Array(path.prefix(1)) + [.scene(match.scene)]
    }
}
