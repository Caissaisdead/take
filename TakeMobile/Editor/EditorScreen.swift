import SwiftUI
import ManuscriptKit

/// A scene on the page, edge to edge. The caption under the title says
/// which text this is and opens the Takes sheet; the menu holds what the
/// Mac's inspector and menus hold; one sheet shows at a time.
struct EditorScreen: View {
    @Environment(ProjectModel.self) private var model
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    @State private var sheet: EditorSheet?
    /// The status line, shown in the caption for a moment after it changes.
    @State private var flash: String?
    @State private var flashTask: Task<Void, Never>?

    enum EditorSheet: Identifiable {
        case takes, compare, versions, scene
        var id: Self { self }
    }

    var body: some View {
        @Bindable var model = model
        MobileEditorView(
            text: model.editorText,
            loadToken: model.loadToken,
            selection: model.editorSelection,
            accent: Accent(rawValue: accentName) ?? .blue,
            onChange: { model.textChanged() },
            onLoad: { model.recordLoad(millis: $0) },
            onReady: { model.editorReady($0) },
            onDismantle: { model.editorGone(text: $0) })
        .ignoresSafeArea(.container, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isInTake { TakeBar() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(model.sceneTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Button {
                        sheet = .takes
                    } label: {
                        HStack(spacing: 3) {
                            Text(flash ?? model.selectionLabel)
                                .lineLimit(1)
                            if flash == nil {
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                            }
                            if model.isDirty {
                                Circle().fill(.orange).frame(width: 6, height: 6)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if model.isInTake {
                        Button("Keep", systemImage: "checkmark.circle") { model.keep() }
                        Button("Discard", systemImage: "xmark.circle") { model.discard() }
                        Divider()
                    }
                    Button("Compare", systemImage: "doc.on.doc") { sheet = .compare }
                    Button("Versions", systemImage: "clock") { sheet = .versions }
                    Button("Scene", systemImage: "note.text") { sheet = .scene }
                    Divider()
                    Button("Takes", systemImage: "arrow.triangle.branch") { sheet = .takes }
                    Button("New Take…", systemImage: "plus") { model.naming = .take }
                    Divider()
                    Button("Save Now", systemImage: "checkmark") { model.save() }
                        .disabled(!model.isDirty)
                }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .takes: TakesSheet()
            case .compare: MobileCompareSheet()
            case .versions: SheetHost(title: "Versions") { VersionsView() }
            case .scene: SheetHost(title: "Scene") { SceneView() }
            }
        }
        .sheet(item: $model.conflict) { conflict in
            MobileConflictSheet(conflict: conflict)
        }
        .namePrompt()
        .onChange(of: model.statusLine) { _, line in show(line) }
        .onAppear {
            // A pose for a screenshot: open the sheet it names.
            switch ProjectModel.shotPose {
            case "compare": sheet = .compare
            case "versions": sheet = .versions
            case "scene-notes": sheet = .scene
            case "takes": sheet = .takes
            default: break
            }
        }
        .onDisappear { model.saveBeforeLeaving() }
    }

    private func show(_ line: String) {
        guard !line.isEmpty else { return }
        flash = line
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            flash = nil
        }
    }
}
