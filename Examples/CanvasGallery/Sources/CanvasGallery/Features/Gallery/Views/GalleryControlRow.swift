import SwiftUI

/// The step button and the backdrop switch above the grid.
struct GalleryControlRow: View {
    let viewModel: GalleryViewModel

    var body: some View {
        HStack {
            Button(Strings.Gallery.step(viewModel.state.step)) {
                viewModel.send(.step)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("step")

            Spacer()

            Toggle(Strings.Gallery.backdrop, isOn: backdropBinding)
                .fixedSize()
                .accessibilityIdentifier("backdrop")
        }
        .padding(.horizontal)
    }

    private var backdropBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state.backdrop },
            set: { _ in viewModel.send(.toggleBackdrop) }
        )
    }
}
