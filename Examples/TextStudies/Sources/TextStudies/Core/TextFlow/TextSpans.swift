import SwiftUI

/// Sorted, merged spans on the x axis, and the free gaps between them.
enum TextSpans {
    static func union(_ spans: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var merged: [ClosedRange<CGFloat>] = []
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, span.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// The parts of `lower...upper` that no excluded span covers and that are at least `minWidth` wide.
    /// `excluded` must be a union, so it is sorted and disjoint.
    static func free(
        from lower: CGFloat, to upper: CGFloat, excluded: [ClosedRange<CGFloat>], minWidth: CGFloat
    ) -> [ClosedRange<CGFloat>] {
        var gaps: [ClosedRange<CGFloat>] = []
        var x = lower
        for span in excluded where span.upperBound > x && span.lowerBound < upper {
            if span.lowerBound > x { gaps.append(x...span.lowerBound) }
            x = max(x, span.upperBound)
        }
        if x < upper { gaps.append(x...upper) }
        return gaps.filter { $0.upperBound - $0.lowerBound >= minWidth }
    }
}
