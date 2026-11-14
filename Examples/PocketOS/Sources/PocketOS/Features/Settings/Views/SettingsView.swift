import SwiftUI

// Settings: connectivity switches, the assistant's key and model, and the display. Each
// value is kept with @AppStorage, so it survives a relaunch; there is no view model.
struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Strings.Settings.title)
                .font(Voice.title(34))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            Form {
                ConnectivitySection()
                AssistantSection()
                DisplaySection()
                Section(Strings.Settings.about) {
                    LabeledContent(Strings.Settings.version, value: Strings.Settings.versionValue)
                }
            }
            .accessibilityIdentifier("settings-form")
        }
    }
}
