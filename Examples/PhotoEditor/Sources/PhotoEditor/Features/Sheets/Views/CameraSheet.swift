import SwiftUI

/// Take Photo. SwiftUI has no camera viewfinder, so the sheet says so instead of showing one.
struct CameraSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                Strings.Sheets.Camera.unavailableTitle,
                systemImage: "camera",
                description: Text(Strings.Sheets.Camera.unavailableDescription)
            )
            .accessibilityIdentifier("camera-unavailable")
            .navigationTitle(Strings.Sheets.Camera.navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                        .accessibilityIdentifier("cancel")
                }
            }
        }
    }
}
