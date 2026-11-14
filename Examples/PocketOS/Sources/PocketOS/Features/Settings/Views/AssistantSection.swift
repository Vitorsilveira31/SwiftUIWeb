import SwiftUI

// The assistant's key and model. The key is kept in @AppStorage, which is UserDefaults, not
// the Keychain: fine for a demo key, not for a real secret.
struct AssistantSection: View {
    @AppStorage("pocketos.assistantKey") private var assistantKey = ""
    @AppStorage("pocketos.assistantModel") private var assistantModel = ChatModel.balanced.rawValue
    @State private var keyDraft = ""

    private var trimmedKey: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Section {
            SecureField(Strings.Settings.assistantKey, text: $keyDraft)
                .accessibilityIdentifier("assistant-key")
            Button(Strings.Settings.saveKey) {
                assistantKey = trimmedKey
                keyDraft = ""
            }
            .disabled(trimmedKey.isEmpty)
            .accessibilityIdentifier("save-key")
            if !assistantKey.isEmpty {
                Button(Strings.Settings.forgetKey, role: .destructive) {
                    assistantKey = ""
                }
                .accessibilityIdentifier("forget-key")
            }
            Picker(Strings.Settings.model, selection: $assistantModel) {
                ForEach(ChatModel.allCases) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            }
            .accessibilityIdentifier("model")
        } header: {
            Text(Strings.Settings.assistant)
        } footer: {
            Text(assistantKey.isEmpty ? Strings.Settings.noKeyFooter : Strings.Settings.savedKeyFooter)
        }
    }
}
