import SwiftUI

/// Everything the breaker needs. Word widths are measured elsewhere; the breaker only sums them.
struct LineBreakInput {
    var widths: [CGFloat]
    /// `breaks[i]` is true when a paragraph ends after word `i`.
    var breaks: [Bool]
    var space: CGFloat
    var lineHeight: CGFloat
    var columns: Int
    var columnWidth: CGFloat
    var gap: CGFloat
    var obstacles: [TextObstacle]
}
