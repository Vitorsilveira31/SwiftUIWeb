import SwiftUI

/// Text flow for the magazine and the spread. Each subview is one word, measured at its ideal
/// size; the layout breaks lines, balances columns by finding the fewest lines that fit, and
/// places every word. When `decorated`, the first three subviews are a drop cap, a pull quote
/// and a round picture, and they are obstacles the words flow around.
struct FlowLayout: Layout {
    var decorated: Bool
    /// Paragraph ends, one per word subview (after the decorations).
    var breaks: [Bool]
    var lineHeight: CGFloat
    var fontSize: CGFloat

    static let columnGap: CGFloat = 28
    static let minColumn: CGFloat = 230

    struct Solution {
        var width: CGFloat
        var height: CGFloat
        var origins: [CGPoint]
        var sizes: [CGSize]
    }

    struct Cache {
        var count: Int = -1
        var measures: [CGSize] = []
        var solution: Solution?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let solution = resolve(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 360, subviews: subviews, cache: &cache)
        return CGSize(width: solution.width, height: solution.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // A NaN or infinite proposal from the host falls back to the same width sizeThatFits uses.
        let solution = resolve(width: bounds.width.isFinite ? bounds.width : 360, subviews: subviews, cache: &cache)
        for index in subviews.indices {
            let origin = solution.origins[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(solution.sizes[index]))
        }
    }

    private var wordStart: Int { decorated ? 3 : 0 }

    private func resolve(width: CGFloat, subviews: Subviews, cache: inout Cache) -> Solution {
        if cache.count != subviews.count {
            cache.measures = (wordStart..<subviews.count).map { subviews[$0].sizeThatFits(.unspecified) }
            cache.count = subviews.count
            cache.solution = nil
        }
        if let solution = cache.solution, solution.width == width {
            return solution
        }
        let solution = solve(width: width, subviews: subviews, measures: cache.measures)
        cache.solution = solution
        return solution
    }

    private func solve(width: CGFloat, subviews: Subviews, measures: [CGSize]) -> Solution {
        let columns: Int
        if decorated {
            columns = width >= 880 ? 3 : (width >= 580 ? 2 : 1)
        } else {
            // Clamp the Double before converting: Int of a huge or NaN value traps in the browser build.
            let fit = (width + Self.columnGap) / (Self.minColumn + Self.columnGap)
            columns = fit.isFinite ? Int(min(5, max(1, fit))) : 1
        }
        let columnWidth = max(
            120, ((width - Self.columnGap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down))

        var origins = [CGPoint](repeating: .zero, count: subviews.count)
        var sizes = [CGSize](repeating: .zero, count: subviews.count)
        var obstacles: [TextObstacle] = []
        var decorationBottom: CGFloat = 0

        if decorated {
            // Positions follow the reference's proportions: the quote on the right, the picture below it.
            let cap = CGRect(x: 0, y: 0, width: 62, height: 72)
            let quoteWidth = min(width, max(220, columnWidth))
            let quoteHeight = subviews[1].sizeThatFits(ProposedViewSize(width: quoteWidth, height: nil)).height
            let quote = CGRect(x: width - quoteWidth, y: lineHeight * 9, width: quoteWidth, height: quoteHeight)
            let diameter = min(180, max(110, columnWidth * 0.55))
            let disc = CGRect(x: 0, y: quote.maxY + lineHeight * 2, width: diameter, height: diameter)

            origins[0] = cap.origin
            sizes[0] = cap.size
            origins[1] = quote.origin
            sizes[1] = quote.size
            origins[2] = disc.origin
            sizes[2] = disc.size
            obstacles = [
                .rect(cap, margin: 8),
                .rect(quote, margin: 16),
                .circle(center: CGPoint(x: disc.midX, y: disc.midY), radius: diameter / 2, margin: 12),
            ]
            decorationBottom = disc.maxY
        }

        let input = LineBreakInput(
            widths: measures.map(\.width),
            breaks: breaks,
            space: fontSize * 0.27,
            lineHeight: lineHeight,
            columns: columns,
            columnWidth: columnWidth,
            gap: Self.columnGap,
            obstacles: obstacles)
        let bands = ColumnBalancer.minimumBands(input)
        let placed = LineBreaker.fill(input, bands: bands).origins
        for (index, origin) in placed.enumerated() {
            let size = measures[index]
            origins[wordStart + index] = CGPoint(x: origin.x, y: origin.y + (lineHeight - size.height) / 2)
            sizes[wordStart + index] = size
        }
        return Solution(
            width: width,
            height: max(CGFloat(bands) * lineHeight, decorationBottom),
            origins: origins,
            sizes: sizes)
    }
}
