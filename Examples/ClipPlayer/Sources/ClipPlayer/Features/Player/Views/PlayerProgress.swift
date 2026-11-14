import SwiftUI

/// Elapsed time, the scrubber bound to the current time, and time left.
struct PlayerProgress: View {
    let viewModel: PlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(ClockText.text(viewModel.state.shownTime))
                .monospacedDigit()
            Slider(
                value: scrubber,
                in: 0...max(viewModel.state.duration, 1),
                onEditingChanged: { editing in
                    if !editing { viewModel.send(.commitScrub) }
                }
            )
            .accessibilityIdentifier("scrubber")
            .accessibilityLabel(Strings.Player.playbackPosition)
            Text(ClockText.text(viewModel.state.remaining, sign: "-"))
                .monospacedDigit()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("progress")
    }

    private var scrubber: Binding<Double> {
        Binding(
            get: { viewModel.state.shownTime },
            set: { viewModel.send(.scrub($0)) }
        )
    }
}
