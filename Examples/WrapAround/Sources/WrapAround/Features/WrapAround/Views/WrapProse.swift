import SwiftUI

/// Words flowed around shapes inside one box of the page. The shapes' decoration is drawn over the same space.
struct WrapProse<Decor: View>: View {
    let metrics: WrapMetrics
    let words: [WrapWord]
    let shapes: [WrapExclusion]
    let region: CGRect
    let paragraphGap: CGFloat
    let height: CGFloat?
    let testId: String
    let decor: Decor

    init(
        metrics: WrapMetrics,
        words: [WrapWord],
        shapes: [WrapExclusion],
        region: CGRect,
        paragraphGap: CGFloat? = nil,
        height: CGFloat? = nil,
        testId: String,
        @ViewBuilder decor: () -> Decor
    ) {
        self.metrics = metrics
        self.words = words
        self.shapes = shapes
        self.region = region
        self.paragraphGap = paragraphGap ?? metrics.lineHeight
        self.height = height
        self.testId = testId
        self.decor = decor()
    }

    var body: some View {
        WrapFlowLayout(
            shapes: shapes,
            region: region,
            lineHeight: metrics.lineHeight,
            paragraphGap: paragraphGap,
            space: metrics.bodySize * 0.28
        ) {
            ForEach(words) { word in
                WrapWordView(word: word)
            }
        }
        .font(.system(size: metrics.bodySize))
        .fontDesign(.serif)
        .frame(width: metrics.proseWidth, height: height, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                decor
            }
        }
        .accessibilityIdentifier(testId)
    }
}
