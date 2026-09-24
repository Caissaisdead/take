import SwiftUI
import ManuscriptKit

struct ContentView: View {
    enum InspectorTab: Hashable { case versions, compare }

    @Environment(ProjectModel.self) private var model
    @State private var showInspector = true
    @State private var inspectorTab: InspectorTab = .versions
    @State private var compareDiff: ProseDiff?
    @State private var compareRefresh: Task<Void, Never>?
    @State private var confirmDiscard = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            BinderView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            DetailView()
        }
        .inspector(isPresented: $showInspector) {
            VStack(spacing: 0) {
                Picker("Inspector", selection: $inspectorTab) {
                    Text("Versions").tag(InspectorTab.versions)
                    Text("Compare").tag(InspectorTab.compare)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                switch inspectorTab {
                case .versions:
                    VersionsView()
                case .compare:
                    CompareView(diff: compareDiff)
                        .equatable()
                }
            }
            .inspectorColumnWidth(min: 280, ideal: inspectorTab == .compare ? 460 : 300, max: 900)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Scene", systemImage: "plus") { model.naming = .scene }
                    .help("Add a scene after the current one (⌘N)")
                Button("Save") { model.save() }
                    .disabled(model.selection == nil)
                Button("New Take") { model.naming = .take }
                    .disabled(model.selection == nil)
                Button("Milestone", systemImage: "flag") { model.naming = .milestone }
                    .help("Mark the whole draft as it stands (⌘M)")
                    .disabled(model.manuscript.scenes.isEmpty)
                if model.isInTake {
                    Button("Keep") { model.keep() }
                    Button("Discard") { confirmDiscard = true }
                }
                Button("Stress") { model.loadStress() }
                    .help("Load the sample scene four times over, about 20k words, as an unsaved edit")
                Toggle("Compare", isOn: compareBinding)
                    .toggleStyle(.button)
                Toggle("Inspector", systemImage: "sidebar.right", isOn: $showInspector)
                    .toggleStyle(.button)
            }
        }
        .sheet(item: $model.naming) { naming in
            NameSheet(naming: naming)
        }
        .sheet(item: $model.conflict) { conflict in
            ConflictSheet(conflict: conflict)
        }
        .confirmationDialog("Discard this take?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Take", role: .destructive) { model.discard() }
        } message: {
            Text("Its ref moves under refs/discarded, so it can be brought back by hand. Unsaved edits are dropped.")
        }
        .onChange(of: comparing) { _, shown in
            if shown { compareDiff = model.compare() }
        }
        .onChange(of: model.selection) {
            if comparing { compareDiff = model.compare() }
        }
        .onChange(of: model.editCount) {
            guard comparing else { return }
            // Debounced: the diff is cheap for a scene, but not cheap enough for every keystroke.
            compareRefresh?.cancel()
            compareRefresh = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                compareDiff = model.compare()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var comparing: Bool {
        showInspector && inspectorTab == .compare
    }

    /// The Compare button: on opens the inspector on the compare tab, off goes
    /// back to versions.
    private var compareBinding: Binding<Bool> {
        Binding(
            get: { comparing },
            set: { on in
                if on {
                    inspectorTab = .compare
                    showInspector = true
                } else {
                    inspectorTab = .versions
                }
            }
        )
    }
}

private struct DetailView: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.selection == nil {
                ContentUnavailableView("No scene open", systemImage: "doc.text", description: Text("Pick a scene in the binder, or add one."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EditorView(
                    text: model.editorText,
                    loadToken: model.loadToken,
                    onChange: { model.textChanged() },
                    onLoad: { model.recordLoad(millis: $0) },
                    onReady: { model.editorReady($0) }
                )
            }
            Divider()
            StatusBar()
        }
    }
}

private struct StatusBar: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Text(model.selectionLabel)
                .fontWeight(.medium)
            if model.isDirty {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes; saved after 10 s idle")
            }
            Text("\(model.wordCount) words")
                .monospacedDigit()
            if let millis = model.lastLoadMillis {
                Text(String(format: "load %.1f ms", millis))
                    .monospacedDigit()
            }
            Spacer()
            Text(model.statusLine)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// One sheet for every name the app asks for: a new take, scene, chapter or
/// part, or a rename.
private struct NameSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let naming: ProjectModel.Naming
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(verb, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .onAppear { name = initialName }
    }

    private var heading: String {
        switch naming {
        case .take: return "New take of “\(model.sceneTitle)”"
        case .scene: return "New scene"
        case .chapter: return "New chapter"
        case .part: return "New part"
        case .milestone: return "Mark a milestone"
        case .rename(let item):
            switch item {
            case .part: return "Rename part"
            case .chapter: return "Rename chapter"
            case .scene: return "Rename scene"
            }
        }
    }

    private var placeholder: String {
        switch naming {
        case .take: return "Take name"
        case .scene: return "Scene title"
        case .chapter: return "Chapter title"
        case .part: return "Part title"
        case .milestone: return "Milestone name, e.g. First draft"
        case .rename: return "Title"
        }
    }

    private var verb: String {
        switch naming {
        case .rename: return "Rename"
        case .milestone: return "Mark"
        default: return "Create"
        }
    }

    private var initialName: String {
        switch naming {
        case .take: return "Take \(model.takes.count + 2)"
        case .scene: return ""
        case .chapter: return "Chapter \(model.manuscript.chapters.count + 1)"
        case .part: return "Part \(model.manuscript.parts.count + 1)"
        case .milestone: return ""
        case .rename(let item): return model.title(of: item)
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        switch naming {
        case .take: model.newTake(named: trimmed)
        case .scene(let chapter, let after): model.addScene(named: trimmed, inChapter: chapter, after: after)
        case .chapter(let part): model.addChapter(named: trimmed, inPart: part)
        case .part: model.addPart(named: trimmed)
        case .milestone: model.markMilestone(named: trimmed)
        case .rename(let item): model.rename(item, to: trimmed)
        }
        dismiss()
    }
}

private struct ConflictSheet: View {
    @Environment(\.dismiss) private var dismiss
    let conflict: ProjectModel.Conflict

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Main changed since this take began")
                .font(.headline)
            Text("Nothing was written. The three texts are shown for reading only.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                column("Base", conflict.base)
                column("Main", conflict.main)
                column("Take", conflict.take)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 1000, minHeight: 560)
    }

    private func column(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .serif))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
