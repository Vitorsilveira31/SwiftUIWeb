import SwiftUI

/// The kicker, the title and the paper switch above the scene chips.
struct WrapHeader: View {
    let viewModel: WrapAroundViewModel
    let metrics: WrapMetrics

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.WrapAround.kicker)
                    .font(.caption2)
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text(Strings.WrapAround.title)
                    .font(.system(size: 30))
                    .fontDesign(.serif)
            }
            Spacer(minLength: 12)
            Button(viewModel.state.dark ? Strings.WrapAround.lightPaper : Strings.WrapAround.darkPaper) {
                viewModel.send(.toggleDarkPaper)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("appearance")
        }
        .frame(width: metrics.pageWidth)
    }
}
