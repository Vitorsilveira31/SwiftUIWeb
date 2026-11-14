import SwiftUI

/// The prose of the selected study, flowed around the shapes its geometry gives for this frame.
struct WrapSceneBody: View {
    let viewModel: WrapAroundViewModel
    let metrics: WrapMetrics
    let elapsedMs: CGFloat

    var body: some View {
        let context = WrapSceneContext(
            elapsedMs: elapsedMs,
            proseWidth: metrics.proseWidth,
            scale: metrics.scale,
            narrow: metrics.narrow,
            orbs: viewModel.state.orbs
        )
        switch viewModel.state.scene {
        case .drag:
            let shapes = DragScene().parts(context)
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.drag).words(narrow: metrics.narrow),
                shapes: shapes,
                region: metrics.region(),
                height: metrics.bodyHeight,
                testId: "drag-prose"
            ) {
                ForEach(viewModel.state.orbs.indices, id: \.self) { index in
                    WrapOrbHandle(viewModel: viewModel, index: index, metrics: metrics)
                }
            }
        case .orbs:
            let shapes = DriftersScene().parts(context)
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.orbs).words(narrow: metrics.narrow),
                shapes: shapes,
                region: metrics.region(),
                height: metrics.bodyHeight,
                testId: "orbs-prose"
            ) {
                WrapPartLayer(shapes: shapes)
            }
        case .dancer:
            let shapes = DancerScene().parts(context)
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.dancer).words(narrow: metrics.narrow),
                shapes: shapes,
                region: metrics.region(),
                height: metrics.bodyHeight,
                testId: "dancer-prose"
            ) {
                WrapPartLayer(shapes: shapes)
            }
        case .ball:
            let shapes = BallScene().parts(context)
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.ball).words(narrow: metrics.narrow),
                shapes: shapes,
                region: metrics.region(),
                height: metrics.bodyHeight,
                testId: "ball-prose"
            ) {
                WrapPartLayer(shapes: shapes)
            }
        case .polygon:
            let shapes = TriangleScene().parts(context)
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.polygon).words(narrow: metrics.narrow),
                shapes: shapes,
                region: metrics.region(),
                height: metrics.bodyHeight,
                testId: "polygon-prose"
            ) {
                WrapPartLayer(shapes: shapes)
            }
        case .editorial:
            WrapEditorialView(viewModel: viewModel, metrics: metrics, context: context)
        case .article:
            let shapes = ArticleScene().parts(context)
            WrapProse(
                metrics: metrics,
                words: viewModel.text(.article).words(narrow: metrics.narrow),
                shapes: shapes,
                region: metrics.region(),
                paragraphGap: 14,
                testId: "article"
            ) {
                WrapPartLayer(shapes: shapes)
            }
        }
    }
}
