import AVFoundation
import SwiftUI

/// The Video screen. The width picks the layout; the keyboard from the note field only changes the height, so the
/// picture shrinks while the same player keeps playing.
struct PlayerView: View {
    @State private var viewModel = PlayerViewModel(repository: SampleClipRepository())
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            Group {
                // The width decides the layout; the keyboard only changes the height.
                if proxy.size.width >= 700 {
                    PlayerWideLayout(viewModel: viewModel, note: $note, focus: $noteFocused)
                } else {
                    PlayerNarrowLayout(viewModel: viewModel, note: $note, focus: $noteFocused)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { viewModel.send(.appear) }
        .onDisappear { viewModel.send(.disappear) }
        .task {
            // The clip loops: when it ends, start again.
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification
            ) {
                viewModel.send(.playbackEnded)
            }
        }
        .task {
            // The notification's userInfo carries the error, but reading it takes a cast from Any, which
            // Embedded Swift (the browser build) cannot do; the message is fixed instead.
            for await _ in NotificationCenter.default.notifications(
                named: AVPlayerItem.failedToPlayToEndTimeNotification
            ) {
                viewModel.send(.playbackFailed)
            }
        }
    }
}
