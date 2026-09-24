import SwiftUI
import ManuscriptKit

struct ContentView: View {
    @Environment(ProjectModel.self) private var model
    @State private var showCompare = false
    @State private var compareDiff: ProseDiff?
    @State private var compareRefresh: Task<Void, Never>?
    @State private var confirmDiscard = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            DetailView()
        }
        .inspector(isPresented: $showCompare) {
            CompareView(diff: compareDiff)
                .equatable()
                .inspectorColumnWidth(min: 320, ideal: 460, max: 900)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Save") { model.save() }
                    .disabled(model.selection == nil)
                Button("New Take") { model.isNamingTake = true }
                    .disabled(model.selection == nil)
                if model.isInTake {
                    Button("Keep") { model.keep() }
                    Button("Discard") { confirmDiscard = true }
                }
                Button("Stress") { model.loadStress() }
                    .help("Load the sample scene four times over, about 20k words, as an unsaved edit")
                Toggle("Compare", isOn: $showCompare)
                    .toggleStyle(.button)
            }
        }
        .sheet(isPresented: $model.isNamingTake) {
            NewTakeSheet(defaultName: "Take \(model.takes.count + 2)")
        }
        .sheet(item: $model.conflict) { conflict in
            ConflictSheet(conflict: conflict)
        }
        .confirmationDialog("Discard this take?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Take", role: .destructive) { model.discard() }
        } message: {
            Text("Its ref moves under refs/discarded, so it can be brought back by hand. Unsaved edits are dropped.")
        }
        .onChange(of: showCompare) { _, shown in
            if shown { compareDiff = model.compare() }
        }
        .onChange(of: model.selection) {
            if showCompare { compareDiff = model.compare() }
        }
        .onChange(of: model.editCount) {
            guard showCompare else { return }
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
}

private struct SidebarView: View {
    @Environment(ProjectModel.self) private var model
    @State private var historyExpanded = true

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(model.manuscript.chapters) { chapter in
                Section(chapter.title) {
                    ForEach(chapter.scenes) { scene in
                        Label(scene.title, systemImage: "doc.text")
                            .tag(ProjectModel.Selection.main(scene.id))
                        if model.selection?.sceneID == scene.id {
                            ForEach(model.takes) { take in
                                Label(take.title, systemImage: "arrow.triangle.branch")
                                    .padding(.leading, 16)
                                    .tag(ProjectModel.Selection.take(take))
                            }
                            DisclosureGroup("History", isExpanded: $historyExpanded) {
                                ForEach(model.history) { version in
                                    VersionRow(version: version)
                                }
                            }
                            .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selectionBinding: Binding<ProjectModel.Selection?> {
        Binding(
            get: { model.selection },
            set: { target in
                // Clicking empty space clears the list selection; the editor keeps its scene.
                if let target, target != model.selection { model.select(target) }
            }
        )
    }
}

private struct VersionRow: View {
    @Environment(ProjectModel.self) private var model
    let version: Version

    var body: some View {
        HStack(spacing: 8) {
            Text(version.id.short)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(version.message)
                    .lineLimit(1)
                Text(version.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Restore") { model.restore(version: version) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

private struct DetailView: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            EditorView(
                text: model.editorText,
                loadToken: model.loadToken,
                onChange: { model.textChanged() },
                onLoad: { model.recordLoad(millis: $0) },
                onReady: { model.editorReady($0) }
            )
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

private struct NewTakeSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(defaultName: String) {
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New take of “\(model.sceneTitle)”")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        model.newTake(named: trimmedName)
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
