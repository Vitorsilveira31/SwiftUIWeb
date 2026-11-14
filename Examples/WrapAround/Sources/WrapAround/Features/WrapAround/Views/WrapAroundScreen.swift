import SwiftUI

/// The studies screen: a header, the scene chips, the study card and the footer.
struct WrapAroundScreen: View {
    @State private var viewModel = WrapAroundViewModel()
    @State private var width: CGFloat = 390

    var body: some View {
        let metrics = WrapMetrics(width: width, largeType: viewModel.state.largeType)
        ScrollView {
            VStack(spacing: 18) {
                WrapHeader(viewModel: viewModel, metrics: metrics)
                WrapSceneChips(viewModel: viewModel, metrics: metrics)
                // The timeline reads the clock at each frame, so the scenes animate without state writes.
                TimelineView(.animation(paused: !viewModel.state.running)) { context in
                    WrapStudyCard(
                        viewModel: viewModel,
                        metrics: metrics,
                        elapsedMs: CGFloat(viewModel.elapsed(at: context.date))
                    )
                }
                WrapFooter(viewModel: viewModel, metrics: metrics)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.narrow ? 18 : 28)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: WrapWidthKey.self, value: proxy.size.width)
                }
            }
        }
        .onPreferenceChange(WrapWidthKey.self) { width = $0 }
        .preferredColorScheme(viewModel.state.dark ? .dark : .light)
    }
}
