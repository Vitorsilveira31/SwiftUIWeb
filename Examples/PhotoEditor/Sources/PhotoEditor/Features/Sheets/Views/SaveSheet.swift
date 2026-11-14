import SwiftUI

/// Save to Photos. SwiftUI can read the library through PhotosPicker but has no API to add to it.
struct SaveSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                Strings.Sheets.Save.unavailableTitle,
                systemImage: "square.and.arrow.down",
                description: Text(Strings.Sheets.Save.unavailableDescription)
            )
            .accessibilityIdentifier("save-unavailable")
            .navigationTitle(Strings.Sheets.Save.navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
            }
        }
    }
}
