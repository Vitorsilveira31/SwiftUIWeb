import SwiftUI

/// The grid of photo buttons: three open sheets, and Export renders the edit.
struct ActionGrid: View {
    let viewModel: EditorViewModel
    @Binding var sheet: EditorSheet?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            Button(Strings.Editor.takePhoto) {
                sheet = .camera
            }
            .accessibilityIdentifier("take-photo")

            Button(Strings.Editor.recentPhotos) {
                sheet = .recents
            }
            .accessibilityIdentifier("show-recents")

            Button(Strings.Editor.orderPrint) {
                sheet = .order
            }
            .accessibilityIdentifier("order-print")

            Button(Strings.Editor.saveToPhotos) {
                sheet = .save
            }
            .accessibilityIdentifier("save")

            Button(Strings.Editor.export) {
                viewModel.send(.export)
            }
            .accessibilityIdentifier("export")
        }
        .buttonStyle(.bordered)
    }
}
