import SwiftUI

/// Rewind, Back 10 s, Play/Pause and Forward 10 s. Icons only, so four buttons fit one phone row; each keeps its
/// words as the accessibility label.
struct PlayerTransport: View {
    let viewModel: PlayerViewModel

    var body: some View {
        HStack(spacing: 8) {
            PlayerTransportButton(title: Strings.Player.rewind, symbol: "backward.end.fill", id: "rewind") {
                viewModel.send(.rewind)
            }
            PlayerTransportButton(title: Strings.Player.back, symbol: "gobackward.10", id: "back") {
                viewModel.send(.seekBack)
            }
            PlayerTransportButton(
                title: viewModel.state.isPlaying ? Strings.Player.pause : Strings.Player.play,
                symbol: viewModel.state.isPlaying ? "pause.fill" : "play.fill",
                id: "toggle"
            ) {
                viewModel.send(.togglePlayback)
            }
            PlayerTransportButton(title: Strings.Player.forward, symbol: "goforward.10", id: "forward") {
                viewModel.send(.seekForward)
            }
        }
    }
}
