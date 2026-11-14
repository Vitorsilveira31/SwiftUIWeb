import SwiftUI

/// Playback rate, mute and volume. Rate is a segmented control because the four values are few and always visible.
struct PlayerSettings: View {
    let viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(Strings.Player.playbackSpeed, selection: rate) {
                Text(Strings.Player.halfSpeed).tag(0.5)
                Text(Strings.Player.normalSpeed).tag(1.0)
                Text(Strings.Player.oneAndHalfSpeed).tag(1.5)
                Text(Strings.Player.doubleSpeed).tag(2.0)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("rate")

            Toggle(Strings.Player.mute, isOn: muted)
                .accessibilityIdentifier("mute")

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                Slider(value: volume, in: 0...1)
                    .accessibilityIdentifier("volume")
                    .accessibilityLabel(Strings.Player.volume)
                Image(systemName: "speaker.wave.3.fill")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var rate: Binding<Double> {
        Binding(
            get: { viewModel.state.rate },
            set: { viewModel.send(.setRate($0)) }
        )
    }

    private var muted: Binding<Bool> {
        Binding(
            get: { viewModel.state.isMuted },
            set: { viewModel.send(.setMuted($0)) }
        )
    }

    private var volume: Binding<Double> {
        Binding(
            get: { viewModel.state.volume },
            set: { viewModel.send(.setVolume($0)) }
        )
    }
}
