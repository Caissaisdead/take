import SwiftUI

/// The project's remote and token, Back Up and Pull with their last times,
/// the targets, the Anthropic key and model, what to ask before a send, the
/// accent, the exports, and the way off this iPhone.
struct ProjectSettingsSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(ProjectIndex.self) private var index
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ConsentGate.alwaysAskKey) private var alwaysAsk = true
    @AppStorage(Accent.key) private var accentName = Accent.blue.rawValue
    /// Hands an export to the binder, which owns the file exporter.
    var export: (ProjectModel.ExportDocument.Kind) -> Void
    var removed: () -> Void

    @State private var remote = ""
    @State private var token = ""
    @State private var hasToken = false
    @State private var key = ""
    @State private var hasKey = APIKeyStore.read() != nil
    @State private var claudeModel = ClaudeClient.model
    @State private var check = ""
    @State private var checking = false
    @State private var showTargets = false
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://github.com/you/novel.git", text: $remote)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { model.backupRemote = remote }
                    HStack {
                        SecureField(hasToken ? "Saved; enter a new one to replace it" : "Access token", text: $token)
                        Button("Save", action: saveToken)
                            .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        Button("Back Up Now") {
                            model.backupRemote = remote
                            model.backUp()
                        }
                        .disabled(remote.trimmingCharacters(in: .whitespaces).isEmpty || model.isBackingUp || model.isPulling)
                        Spacer()
                        Button("Pull Now") {
                            model.backupRemote = remote
                            model.pull()
                        }
                        .disabled(remote.trimmingCharacters(in: .whitespaces).isEmpty || model.isBackingUp || model.isPulling)
                        if model.isBackingUp || model.isPulling { ProgressView() }
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Remote")
                } footer: {
                    Text(remoteFooter)
                }

                Section {
                    Button("Targets…") { showTargets = true }
                } footer: {
                    Text(targetsFooter)
                }

                Section {
                    HStack {
                        SecureField("sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save", action: saveKey)
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Picker("Model", selection: $claudeModel) {
                        ForEach(ClaudeClient.models, id: \.id) { entry in
                            Text(entry.name).tag(entry.id)
                        }
                    }
                    .onChange(of: claudeModel) { _, chosen in
                        UserDefaults.standard.set(chosen, forKey: ClaudeClient.modelKey)
                    }
                    HStack {
                        Button("Check Key", action: runCheck)
                            .disabled(!hasKey || checking)
                        if checking { ProgressView() }
                        Spacer()
                        if hasKey {
                            Button("Remove Key", role: .destructive) {
                                APIKeyStore.write("")
                                hasKey = false
                                check = ""
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    if !check.isEmpty {
                        Text(check).font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Ask before each send", isOn: $alwaysAsk)
                } header: {
                    Text("Anthropic")
                } footer: {
                    Text((hasKey ? "A key is saved in this iPhone's keychain. " : "No key saved. ") + "Your key, your account, your bill. Three Takes sends the open scene, its neighbours and the Untangle beat sheet under it; Untangle sends nothing; Back Up sends the project to the remote above. Nothing else leaves.")
                }

                Section {
                    HStack(spacing: 12) {
                        ForEach(Accent.allCases) { accent in
                            Button {
                                accentName = accent.rawValue
                            } label: {
                                ZStack {
                                    Circle().fill(accent.color).frame(width: 28, height: 28)
                                    if accent.rawValue == accentName {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.name)
                        }
                    }
                } header: {
                    Text("Accent")
                } footer: {
                    Text("The colour of controls, selections and live takes. Yours on this iPhone; never part of a project.")
                }

                Section("Export") {
                    Button("Markdown to Files…") { dismiss(); export(.markdown) }
                    Button("PDF to Files…") { dismiss(); export(.pdf) }
                }

                Section {
                    Button("Remove from this iPhone", role: .destructive) { confirmingRemoval = true }
                } footer: {
                    Text("Only the copy on this iPhone goes. The remote and the Mac keep everything, takes and all.")
                }
            }
            .navigationTitle(model.projectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.backupRemote = remote
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showTargets) { MobileTargetsSheet() }
            .confirmationDialog("Remove “\(model.projectName)” from this iPhone?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove from this iPhone", role: .destructive) { remove() }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            remote = model.backupRemote
            hasToken = model.backupToken() != nil
        }
    }

    private var remoteFooter: String {
        var lines = ["Back Up pushes main, the milestones and every take to this remote over HTTPS with the token, which lives in this iPhone's keychain with the project. Pull brings the remote's down: main moves forward when only the remote changed, and when both changed, this iPhone's text is kept as takes."]
        let when: (Date) -> String = { $0.formatted(.relative(presentation: .named)) }
        if let last = model.lastBackup { lines.append("Backed up \(when(last)).") }
        if let last = model.lastPull { lines.append("Pulled \(when(last)).") }
        return lines.joined(separator: " ")
    }

    private var targetsFooter: String {
        var parts: [String] = []
        if let target = model.manuscript.target { parts.append("\(target.formatted()) words for the draft") }
        if let daily = model.manuscript.dailyTarget { parts.append("\(daily.formatted()) a day") }
        return parts.isEmpty ? "No targets set." : parts.joined(separator: ", ") + "."
    }

    private func saveToken() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = model.projectURL else { return }
        hasToken = ProjectModel.tokenItem(for: url).write(trimmed)
        token = ""
    }

    private func saveKey() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasKey = APIKeyStore.write(trimmed)
        key = ""
        check = hasKey ? "Saved." : "The keychain refused the key."
    }

    private func runCheck() {
        checking = true
        check = ""
        Task {
            do {
                check = try await ClaudeClient.checkKey()
            } catch {
                check = error.localizedDescription
            }
            checking = false
        }
    }

    private func remove() {
        guard let url = model.projectURL, let entry = index.entries.first(where: { $0.folder == url }) else { return }
        model.close()
        guard model.projectURL == nil else { return }
        index.remove(entry)
        dismiss()
        removed()
    }
}
