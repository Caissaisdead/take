import SwiftUI

/// The one name sheet the phone has: an alert with a field, driven by the
/// model's `naming`, the same as the Mac's sheet.
struct NamePrompt: ViewModifier {
    @Environment(ProjectModel.self) private var model
    @State private var name = ""

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert(title, isPresented: Binding(get: { model.naming != nil }, set: { if !$0 { model.naming = nil } })) {
                TextField(placeholder, text: $name)
                Button("Cancel", role: .cancel) {}
                Button(verb, action: commit)
            }
            .onChange(of: model.naming) { _, naming in
                guard let naming else { return }
                name = initialName(for: naming)
            }
    }

    private var title: String {
        switch model.naming {
        case .take: return "New Take"
        case .scene: return "New Scene"
        case .chapter: return "New Chapter"
        case .part: return "New Part"
        case .milestone: return "Mark a Milestone"
        case .rename(let item):
            switch item {
            case .part: return "Rename Part"
            case .chapter: return "Rename Chapter"
            case .scene: return "Rename Scene"
            }
        case nil: return ""
        }
    }

    private var placeholder: String {
        switch model.naming {
        case .take: return "Take name"
        case .scene: return "Scene title"
        case .chapter: return "Chapter title"
        case .part: return "Part title"
        case .milestone: return "Milestone name, e.g. First draft"
        case .rename, nil: return "Title"
        }
    }

    private var verb: String {
        switch model.naming {
        case .rename: return "Rename"
        case .milestone: return "Mark"
        default: return "Create"
        }
    }

    private func initialName(for naming: ProjectModel.Naming) -> String {
        switch naming {
        case .take: return "Take \(model.takes.count + 2)"
        case .scene: return ""
        case .chapter: return "Chapter \(model.manuscript.chapters.count + 1)"
        case .part: return "Part \(model.manuscript.parts.count + 1)"
        case .milestone: return ""
        case .rename(let item): return model.title(of: item)
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let naming = model.naming else { return }
        switch naming {
        case .take: model.newTake(named: trimmed)
        case .scene(let chapter, let after): model.addScene(named: trimmed, inChapter: chapter, after: after)
        case .chapter(let part): model.addChapter(named: trimmed, inPart: part)
        case .part: model.addPart(named: trimmed)
        case .milestone: model.markMilestone(named: trimmed)
        case .rename(let item): model.rename(item, to: trimmed)
        }
    }
}

extension View {
    func namePrompt() -> some View { modifier(NamePrompt()) }
}
