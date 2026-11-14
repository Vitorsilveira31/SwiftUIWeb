import SwiftUI

/// One column for a phone: the clip menu on top, the controls under the picture, the note last.
struct PlayerNarrowLayout: View {
    let viewModel: PlayerViewModel
    @Binding var note: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 12) {
            PlayerClipMenu(viewModel: viewModel)
            PlayerTransport(viewModel: viewModel)
            PlayerSurface(viewModel: viewModel)
            PlayerProgress(viewModel: viewModel)
            PlayerFailureLine(viewModel: viewModel)
            PlayerSettings(viewModel: viewModel)
            PlayerNote(note: $note, focus: focus)
        }
    }
}
