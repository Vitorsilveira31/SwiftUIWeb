import SwiftUI

/// One icon-only button of the transport row, bordered, with its title as the accessibility label.
struct PlayerTransportButton: View {
    let title: String
    let symbol: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }
}
