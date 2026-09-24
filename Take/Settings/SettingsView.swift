import SwiftUI

/// Settings: the Anthropic key and model, and what leaves the Mac. The key
/// goes to the keychain the moment it is saved and is never shown again.
struct SettingsView: View {
    @State private var key = ""
    @State private var hasKey = APIKeyStore.read() != nil
    @State private var model = ClaudeClient.model
    @State private var check = ""
    @State private var checking = false
    @AppStorage(ConsentGate.alwaysAskKey) private var alwaysAsk = true

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("sk-ant-…", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Text(hasKey ? "A key is saved in the keychain." : "No key saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if hasKey {
                        Button("Remove Key") {
                            APIKeyStore.write("")
                            hasKey = false
                            check = ""
                        }
                        .controlSize(.small)
                    }
                }
                Picker("Model", selection: $model) {
                    ForEach(ClaudeClient.models, id: \.id) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
                .onChange(of: model) { _, chosen in
                    UserDefaults.standard.set(chosen, forKey: ClaudeClient.modelKey)
                }
                HStack {
                    Button("Check Key") { runCheck() }
                        .disabled(!hasKey || checking)
                    if checking { ProgressView().controlSize(.small) }
                    Text(check)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Anthropic")
            } footer: {
                Text("Your key, your account, your bill. Take never sees or stores it anywhere but this Mac's keychain.")
            }

            Section {
                Toggle("Ask before each send", isOn: $alwaysAsk)
            } header: {
                Text("What leaves the Mac")
            } footer: {
                Text("Untangle runs on Apple's on-device model and sends nothing. Three Takes sends the open scene, the scenes on either side of it, and the Untangle beat sheet if there is one, to Anthropic under your key. Nothing else ever leaves.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }

    private func save() {
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
}

/// Whether the writer has agreed to text leaving the Mac, and how often to ask.
enum ConsentGate {
    static let alwaysAskKey = "ConsentAlwaysAsk"
    static let agreedKey = "ConsentAgreed"

    /// True when no sheet is needed: the writer agreed once and asked not to
    /// be asked again.
    static var isSettled: Bool {
        UserDefaults.standard.bool(forKey: agreedKey) && !(UserDefaults.standard.object(forKey: alwaysAskKey) as? Bool ?? true)
    }

    static func agree(alwaysAsk: Bool) {
        UserDefaults.standard.set(true, forKey: agreedKey)
        UserDefaults.standard.set(alwaysAsk, forKey: alwaysAskKey)
    }
}
