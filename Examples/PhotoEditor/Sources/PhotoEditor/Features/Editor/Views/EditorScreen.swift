import PhotosUI
import SwiftUI

/// The editor's one screen: the photo, its readout and controls, and the sheets it opens over itself.
struct EditorScreen: View {
    @State private var viewModel = EditorViewModel()
    /// Print orders live as long as the screen, so the orders list survives closing the sheet.
    @State private var printOrder = PrintOrderViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var sheet: EditorSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EditorSurface(viewModel: viewModel)
                    .accessibilityIdentifier("editor")

                EditReadout(viewModel: viewModel)
                TurnAndUndoRow(viewModel: viewModel)
                FilterRow(viewModel: viewModel)
                AdjustmentSliders(viewModel: viewModel)
                PhotoActions(viewModel: viewModel, sheet: $sheet)
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(Strings.Editor.choosePhoto, systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("choose-photo")
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            viewModel.send(.pickPhoto(item))
            pickerItem = nil
        }
        .onChange(of: viewModel.state.picks) { _, _ in
            sheet = nil
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .camera:
                CameraSheet()
            case .recents:
                RecentsSheet(selection: $pickerItem)
            case .save:
                SaveSheet()
            case .order:
                PrintOrderSheet(viewModel: printOrder)
            }
        }
    }
}
