import SwiftUI

struct AboutScreen: View {
    @Binding var darkMode: Bool
    @AppStorage("trio.name") var name = ""

    var body: some View {
        Form {
            Section("Running now") {
                LabeledContent("Platform", value: RuntimePlatform.name)
                LabeledContent("Engine", value: RuntimePlatform.engine)
            }

            Section("You") {
                TextField("Your name", text: $name)
                Text(name.isEmpty ? "Hello!" : "Hello, \(name)!")
                    .font(.headline)
                Toggle("Dark mode", isOn: $darkMode)
            }

            Section {
                Text("The same Swift code in Sources/Trio runs on iOS (SwiftUI), Android (Skip) and the Web (SwiftUIWeb).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
    }
}
