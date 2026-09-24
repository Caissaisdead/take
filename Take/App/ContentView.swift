import SwiftUI
import ManuscriptKit

struct ContentView: View {
    enum InspectorTab: Hashable { case versions, compare, untangle }

    @Environment(ProjectModel.self) private var model
    @State private var showInspector = true
    @State private var showMap = false
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
            if showMap {
                MapView()
            } else {
                DetailView()
            }
        }
        .inspector(isPresented: $showInspector) {
            VStack(spacing: 0) {
                Picker("Inspector", selection: $inspectorTab) {
                    Text("Versions").tag(InspectorTab.versions)
                    Text("Compare").tag(InspectorTab.compare)
                    Text("Untangle").tag(InspectorTab.untangle)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                switch inspectorTab {
                case .versions:
                    VersionsView()
                case .compare:
                    Picker("Against", selection: $model.compareBase) {
                        ForEach(model.compareChoices, id: \.base) { choice in
                            Text(choice.label).tag(choice.base)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .disabled(model.selection == nil)
                    CompareView(diff: compareDiff)
                        .equatable()
                case .untangle:
                    UntangleView()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showUntangle)) { _ in
                inspectorTab = .untangle
                showInspector = true
                model.untangle()
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
                if ProjectModel.isBenchRequested {
                    Button("Stress") { model.loadStress() }
                        .help("Load the sample scene four times over, about 20k words; not saved unless you save")
                }
                Toggle("Compare", isOn: compareBinding)
                    .toggleStyle(.button)
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .help("Compare the editor with another version (⇧⌘D)")
                Toggle("Map", systemImage: "map", isOn: $showMap)
                    .toggleStyle(.button)
                    .keyboardShortcut("m", modifiers: [.command, .option])
                    .help("Map the chapter: scenes in a line, takes beneath (⌥⌘M)")
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
        .sheet(isPresented: $model.consent) {
            ConsentSheet()
        }
        .sheet(isPresented: Binding(get: { model.takeRuns != nil }, set: { if !$0 { model.cancelThreeTakes() } })) {
            ThreeTakesSheet()
        }
        .confirmationDialog("Discard this take?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Take", role: .destructive) { model.discard() }
        } message: {
            Text("It moves to the scene's discarded list, where Restore brings it back. Unsaved edits are dropped.")
        }
        .onChange(of: comparing) { _, shown in
            if shown { compareDiff = model.compare() }
        }
        .onChange(of: model.selection) {
            if comparing { compareDiff = model.compare() }
        }
        .onChange(of: model.compareBase) {
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
        .navigationTitle(model.projectName)
        .navigationSubtitle((model.projectURL?.deletingLastPathComponent().path(percentEncoded: false) as NSString?)?.abbreviatingWithTildeInPath ?? "")
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
                    onReady: { model.editorReady($0) },
                    onDismantle: { model.editorGone(text: $0) }
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
            if ProjectModel.isBenchRequested, let millis = model.lastLoadMillis {
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

/// A keep that met a moved main: the three texts side by side, and a choice of
/// whole scene. Paragraph-level picking is not offered; a writer's merge is a
/// selection.
/// Asked before the first send, and every time unless the writer says not to.
private struct ConsentSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var alwaysAsk = !(UserDefaults.standard.object(forKey: ConsentGate.alwaysAskKey) as? Bool == false)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send this scene to Anthropic?")
                .font(.headline)
            Text("Three Takes sends the open scene, the scenes on either side of it, and the Untangle beat sheet if there is one, to Anthropic's API under your own key. Anthropic's usage policy and privacy terms apply. Nothing else leaves this Mac, and Untangle never sends anything.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Ask every time", isOn: $alwaysAsk)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Send") {
                    ConsentGate.agree(alwaysAsk: alwaysAsk)
                    dismiss()
                    model.writeThreeTakes()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// The three angles and how far each has got.
private struct ThreeTakesSheet: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Three takes of “\(model.sceneTitle)”")
                .font(.headline)
            Text("Written one after another on \(ClaudeClient.model), each told what the earlier ones did.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(model.takeRuns ?? []) { run in
                HStack(alignment: .top, spacing: 10) {
                    icon(for: run.state)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take \(run.angle.id): \(run.angle.name)")
                            .fontWeight(.medium)
                        Text(run.angle.card)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail(for: run.state))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            HStack {
                Spacer()
                Button(model.isWritingTakes ? "Stop" : "Done") { model.cancelThreeTakes() }
                    .keyboardShortcut(model.isWritingTakes ? .cancelAction : .defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private func icon(for state: ProjectModel.TakeRun.State) -> some View {
        switch state {
        case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .writing: ProgressView().controlSize(.small)
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

private struct ConflictSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let conflict: ProjectModel.Conflict

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Main changed since “\(conflict.take.name)” began")
                .font(.headline)
            Text("Nothing has been written. Keep one whole scene; the other stays in history either way.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                column("Where both began", conflict.base)
                column("Main now", conflict.main)
                column("The take", conflict.text)
            }
            HStack {
                Button("Keep Main’s Text") { model.settle(conflict, choosing: .main) }
                Button("Keep the Take’s Text") { model.settle(conflict, choosing: .take) }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Decide Later") { dismiss() }
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

extension Notification.Name {
    /// Draft > Untangle: open the pane and run it.
    static let showUntangle = Notification.Name("TakeShowUntangle")
}
