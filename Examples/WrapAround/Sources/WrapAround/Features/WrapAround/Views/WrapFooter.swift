import SwiftUI

/// The footnote and the type-size and pause controls below the study card.
struct WrapFooter: View {
    let viewModel: WrapAroundViewModel
    let metrics: WrapMetrics

    var body: some View {
        HStack(spacing: 6) {
            Text(Strings.WrapAround.footnote)
                .italic()
                .font(.caption)
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(viewModel.state.largeType ? Strings.WrapAround.typeLarge : Strings.WrapAround.typeStandard) {
                withAnimation(.smooth) { viewModel.send(.toggleLargeType) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("type-size")
            Button(viewModel.state.running ? Strings.WrapAround.pause : Strings.WrapAround.play) {
                viewModel.send(.togglePause)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("pause")
        }
        .frame(width: metrics.pageWidth)
    }
}
