import SwiftUI

// The three connectivity switches. Airplane Mode turns Wi-Fi off, as on the phone it imitates.
struct ConnectivitySection: View {
    @AppStorage("pocketos.airplane") private var airplane = false
    @AppStorage("pocketos.wifi") private var wifi = true
    @AppStorage("pocketos.bluetooth") private var bluetooth = true

    var body: some View {
        Section(Strings.Settings.connectivity) {
            Toggle(Strings.Settings.airplane, isOn: $airplane)
                .accessibilityIdentifier("switch-airplane")
            Toggle(Strings.Settings.wifi, isOn: $wifi)
                .disabled(airplane)
                .accessibilityIdentifier("switch-wifi")
            Toggle(Strings.Settings.bluetooth, isOn: $bluetooth)
                .accessibilityIdentifier("switch-bluetooth")
        }
        .onChange(of: airplane) { _, on in
            if on {
                wifi = false
            }
        }
    }
}
