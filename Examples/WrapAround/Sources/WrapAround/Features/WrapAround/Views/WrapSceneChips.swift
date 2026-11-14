import SwiftUI

/// The row of study chips, wrapping onto as many lines as the width needs.
struct WrapSceneChips: View {
    let viewModel: WrapAroundViewModel
    let metrics: WrapMetrics

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.narrow ? 96 : 116), spacing: 6)], spacing: 6) {
            ForEach(WrapScene.allCases) { scene in
                WrapSceneChip(viewModel: viewModel, scene: scene)
            }
        }
        .frame(width: metrics.pageWidth)
    }
}
