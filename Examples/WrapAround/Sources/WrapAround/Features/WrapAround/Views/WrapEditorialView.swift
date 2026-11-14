import SwiftUI

/// Study 05: two columns that share one set of exclusions. The shapes are drawn once, over the left column.
struct WrapEditorialView: View {
    let viewModel: WrapAroundViewModel
    let metrics: WrapMetrics
    let context: WrapSceneContext

    var body: some View {
        let shapes = EditorialScene().parts(context)
        let columnWidth = metrics.narrow ? metrics.proseWidth : (metrics.proseWidth - 32) / 2
        let height: CGFloat = metrics.narrow ? 992 : 530
        ZStack(alignment: .topLeading) {
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.editorialLeft).wide,
                shapes: shapes,
                region: metrics.region(width: columnWidth),
                height: height,
                testId: "editorial-left"
            ) {
                WrapPartLayer(shapes: shapes)
            }
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.editorialRight).wide,
                shapes: shapes,
                region: metrics.region(
                    width: columnWidth,
                    x: metrics.narrow ? 0 : (metrics.proseWidth + 32) / 2,
                    y: metrics.narrow ? 542 : 0
                ),
                height: height,
                testId: "editorial-right"
            ) {
                EmptyView()
            }
        }
    }
}
