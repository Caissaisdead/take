import SwiftUI

/// A URL and a token, the same two the Mac backs up with: the phone clones
/// into its own container and opens what came down.
struct AddProjectSheet: View {
    @Environment(ProjectIndex.self) private var index
    @Environment(\.dismiss) private var dismiss
    var opened: (ProjectEntry) -> Void

    @State private var remote = ""
    @State private var token = ""
    @State private var isCloning = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://github.com/you/novel.git", text: $remote)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Access token", text: $token)
                } header: {
                    Text("Remote")
                } footer: {
                    Text("The repository the Mac backs up to, over HTTPS, with a personal access token that can read and push it. The token stays in this iPhone's keychain with the project.")
                }
                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Pull a Draft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCloning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCloning {
                        ProgressView()
                    } else {
                        Button("Pull", action: clone)
                            .disabled(remote.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isCloning)
        }
    }

    private func clone() {
        let url = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        isCloning = true
        failure = nil
        Task {
            do {
                let entry = try await index.clone(remote: url, token: token)
                isCloning = false
                dismiss()
                opened(entry)
            } catch {
                isCloning = false
                failure = "Could not pull: " + ProjectModel.plain(error)
            }
        }
    }
}
