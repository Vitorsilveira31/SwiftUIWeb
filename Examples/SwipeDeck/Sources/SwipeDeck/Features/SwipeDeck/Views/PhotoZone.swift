import SwiftUI

/// A half of the photo area: a tap pages to the previous or next photo.
struct PhotoZone: View {
    let identifier: String
    let label: String
    let onTap: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
    }
}
