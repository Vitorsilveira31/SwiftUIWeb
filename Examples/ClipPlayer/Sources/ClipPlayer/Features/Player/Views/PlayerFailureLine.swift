import SwiftUI

/// The playback error in red, shown only when there is one.
struct PlayerFailureLine: View {
    let viewModel: PlayerViewModel

    var body: some View {
        if !viewModel.state.failure.isEmpty {
            Text(viewModel.state.failure)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("video-error")
        }
    }
}
