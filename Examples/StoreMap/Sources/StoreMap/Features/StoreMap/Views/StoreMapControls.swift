import SwiftUI

struct StoreMapControls: View {
    let viewModel: StoreMapViewModel

    var body: some View {
        VStack(spacing: 8) {
            StorePickRow(viewModel: viewModel)
            StoreZoomRow(viewModel: viewModel)
            Text(Strings.Stores.pinsSelected(viewModel.state.picks))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("picks")
            Text(Strings.Stores.zoom(viewModel.state.zoom.displayLevel))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("zoom")
        }
        .padding(12)
    }
}
