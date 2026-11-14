import SwiftUI

/// Masonry: each subview goes into the shortest column. A card's height comes from its own
/// text measurement at the column width; the result is cached per width and seed.
struct MasonryLayout: Layout {
    /// Changing the seed changes the cards, so it must invalidate the cache even when the count is equal.
    var seed: Int

    struct Cache {
        var width: CGFloat = -1
        var seed: Int = Int.min
        var count: Int = -1
        var columnWidth: CGFloat = 0
        var origins: [CGPoint] = []
        var heights: [CGFloat] = []
        var tallest: CGFloat = 0
    }

    static let gap: CGFloat = 16
    static let minColumn: CGFloat = 240

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = Self.usableWidth(proposal.width)
        update(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.tallest)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        update(width: Self.usableWidth(bounds.width), subviews: subviews, cache: &cache)
        for index in subviews.indices {
            let origin = cache.origins[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: cache.columnWidth, height: cache.heights[index]))
        }
    }

    private static func usableWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return 360 }
        return proposed
    }

    private func update(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard width != cache.width || seed != cache.seed || subviews.count != cache.count else { return }
        // Clamp the Double before converting: Int of a huge or NaN value traps in the browser build.
        let fit = (width + Self.gap) / (Self.minColumn + Self.gap)
        let columns = fit.isFinite ? Int(min(5, max(1, fit))) : 1
        let column = ((width - Self.gap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        var tops = [CGFloat](repeating: 0, count: columns)
        var origins: [CGPoint] = []
        var heights: [CGFloat] = []
        origins.reserveCapacity(subviews.count)
        heights.reserveCapacity(subviews.count)
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            let shortest = tops.indices.min { tops[$0] < tops[$1] } ?? 0
            origins.append(CGPoint(x: CGFloat(shortest) * (column + Self.gap), y: tops[shortest]))
            heights.append(height)
            tops[shortest] += height + Self.gap
        }
        cache = Cache(
            width: width,
            seed: seed,
            count: subviews.count,
            columnWidth: column,
            origins: origins,
            heights: heights,
            tallest: max(0, (tops.max() ?? 0) - Self.gap))
    }
}
