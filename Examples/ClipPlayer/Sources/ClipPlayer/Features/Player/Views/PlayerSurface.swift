import AVKit
import SwiftUI

/// The picture with AVKit's own controls, including full screen and Picture in Picture.
struct PlayerSurface: View {
    let viewModel: PlayerViewModel

    var body: some View {
        VideoPlayer(player: viewModel.player)
            .accessibilityIdentifier("video")
            .accessibilityLabel(viewModel.state.clip.map { Strings.Player.videoLabel($0.title) } ?? "")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
