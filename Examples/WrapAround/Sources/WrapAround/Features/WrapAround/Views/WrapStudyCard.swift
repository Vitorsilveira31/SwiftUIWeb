import SwiftUI

/// The card of the selected study: its eyebrow, title and subtitle, then the wrapped prose.
struct WrapStudyCard: View {
    let viewModel: WrapAroundViewModel
    let metrics: WrapMetrics
    let elapsedMs: CGFloat

    var body: some View {
        let scene = viewModel.state.scene
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text(scene.eyebrow)
                    .font(.caption2)
                    .tracking(2)
                    .foregroundStyle(WrapTint.terracotta.color)
                Text(scene.title)
                    .font(.system(size: metrics.titleSize))
                    .fontDesign(.serif)
                    .tracking(-0.6)
                Text(scene.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WrapSceneBody(viewModel: viewModel, metrics: metrics, elapsedMs: elapsedMs)
        }
        .padding(metrics.inset)
        .frame(width: metrics.pageWidth, alignment: .leading)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}
