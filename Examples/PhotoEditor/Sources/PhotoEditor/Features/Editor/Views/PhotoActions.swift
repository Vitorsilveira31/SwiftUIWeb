import SwiftUI

/// The photo's actions: the grid of buttons, and the share link once an export exists.
struct PhotoActions: View {
    let viewModel: EditorViewModel
    @Binding var sheet: EditorSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Editor.photo)
                .font(.headline)
            ActionGrid(viewModel: viewModel, sheet: $sheet)
            if let exported = viewModel.state.exported {
                ExportShare(image: exported)
            }
        }
    }
}
