import SwiftUI

/// Places word subviews left to right, line by line, skipping the spans the shapes cover.
/// A line may be split around a shape, so words continue in the free span after it.
struct WrapFlowLayout: Layout {
    var shapes: [WrapExclusion]
    var region: CGRect
    var lineHeight: CGFloat
    var paragraphGap: CGFloat
    var space: CGFloat

    /// Line advances allowed for one word; a word that still fits nowhere after this is not placed.
    private static let maxAttemptsPerWord = 5_000

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? region.maxX, height: place(subviews).bottom)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = place(subviews)
        for index in subviews.indices {
            guard let origin = placed.origins[index] else { continue }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func place(_ subviews: Subviews) -> (origins: [CGPoint?], bottom: CGFloat) {
        var origins = [CGPoint?](repeating: nil, count: subviews.count)
        var bottom: CGFloat = 0
        var y = region.minY
        var spans: [Range<CGFloat>] = []
        var span = 0
        var x = region.minX
        var lineEmpty = true

        func startLine() {
            spans = freeSpans(top: y)
            span = 0
            x = spans.first?.lowerBound ?? region.minX
            lineEmpty = true
        }
        startLine()

        for index in subviews.indices {
            if subviews[index][WrapBreakKey.self] {
                y += lineHeight + paragraphGap
                startLine()
                continue
            }
            let width = subviews[index].sizeThatFits(.unspecified).width
            var attempts = 0
            while true {
                // Shapes can block every line; stop after a bounded number of tries and leave the word unplaced.
                attempts += 1
                if attempts > Self.maxAttemptsPerWord { break }
                if spans.isEmpty {
                    y += lineHeight
                    startLine()
                    continue
                }
                if x + width <= spans[span].upperBound { break }
                if span + 1 < spans.count {
                    span += 1
                    x = spans[span].lowerBound
                    continue
                }
                // A word wider than every free span is placed alone rather than dropped.
                if lineEmpty { break }
                y += lineHeight
                startLine()
            }
            if attempts > Self.maxAttemptsPerWord { continue }
            origins[index] = CGPoint(x: x, y: y)
            x += width + space
            lineEmpty = false
            bottom = max(bottom, y + lineHeight)
        }
        return (origins, bottom)
    }

    /// Free horizontal spans on the line band starting at `top`, sampled at four heights.
    private func freeSpans(top: CGFloat) -> [Range<CGFloat>] {
        var blocked: [Range<CGFloat>] = []
        for shape in shapes {
            for step in 0...3 {
                blocked += shape.intervals(at: top + lineHeight * CGFloat(step) / 3)
            }
        }
        blocked.sort { $0.lowerBound < $1.lowerBound }
        var free: [Range<CGFloat>] = []
        var cursor = region.minX
        for gap in blocked {
            let end = min(gap.lowerBound, region.maxX)
            if end > cursor { free.append(cursor..<end) }
            cursor = max(cursor, gap.upperBound)
        }
        if region.maxX > cursor { free.append(cursor..<region.maxX) }
        return free.filter { $0.upperBound - $0.lowerBound >= 14 }
    }
}
