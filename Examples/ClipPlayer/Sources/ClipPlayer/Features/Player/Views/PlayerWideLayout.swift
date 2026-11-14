import SwiftUI

/// Wide screens: the player and its controls on the left, the clip list and settings in a side column.
struct PlayerWideLayout: View {
    let viewModel: PlayerViewModel
    @Binding var note: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                PlayerTransport(viewModel: viewModel)
                PlayerSurface(viewModel: viewModel)
                PlayerProgress(viewModel: viewModel)
                PlayerFailureLine(viewModel: viewModel)
                PlayerNote(note: $note, focus: focus)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PlayerClipRows(viewModel: viewModel)
                    PlayerSettings(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 260)
        }
    }
}
