import PhotosUI
import SwiftUI

/// Recents. The library cannot be listed from SwiftUI, so the sheet offers the picker that can read it.
struct RecentsSheet: View {
    @Binding var selection: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(Strings.Sheets.Recents.unavailableTitle, systemImage: "photo.on.rectangle")
            } description: {
                Text(Strings.Sheets.Recents.unavailableDescription)
            } actions: {
                PhotosPicker(Strings.Sheets.Recents.chooseFromLibrary, selection: $selection, matching: .images)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("choose-from-library")
            }
            .accessibilityIdentifier("recents-unavailable")
            .navigationTitle(Strings.Sheets.Recents.navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
            }
        }
    }
}
