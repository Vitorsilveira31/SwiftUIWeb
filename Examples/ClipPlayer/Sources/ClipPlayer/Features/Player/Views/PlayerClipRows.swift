import SwiftUI

/// The clip list in the side column on a wide screen, with the current one marked.
struct PlayerClipRows: View {
    let viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Player.clipsHeading)
                .font(.headline)
            ForEach(viewModel.state.clips) { clip in
                PlayerClipRow(clip: clip, isCurrent: clip == viewModel.state.clip) {
                    viewModel.send(.selectClip(clip))
                }
            }
        }
    }
}
