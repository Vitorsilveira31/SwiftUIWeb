import SwiftUI

/// The clip chooser on a phone: one row with a menu, as the reference's select.
struct PlayerClipMenu: View {
    let viewModel: PlayerViewModel

    var body: some View {
        Picker(Strings.Player.clipPicker, selection: selection) {
            ForEach(viewModel.state.clips) { clip in
                Text(clip.title).tag(Optional(clip))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("source")
    }

    private var selection: Binding<Clip?> {
        Binding(
            get: { viewModel.state.clip },
            set: { chosen in
                if let chosen { viewModel.send(.selectClip(chosen)) }
            }
        )
    }
}
