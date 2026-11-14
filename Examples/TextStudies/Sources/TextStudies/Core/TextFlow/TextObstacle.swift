import SwiftUI

/// A shape the words flow around, in the coordinates of the page being flowed.
enum TextObstacle: Sendable {
    case circle(center: CGPoint, radius: CGFloat, margin: CGFloat)
    case rect(CGRect, margin: CGFloat)
    case polygon([CGPoint], margin: CGFloat)

    /// The horizontal spans this shape covers within one line band. Sampling the top,
    /// middle and bottom of the band keeps the exclusion honest for a sloped edge.
    func excluded(top: CGFloat, bottom: CGFloat) -> [ClosedRange<CGFloat>] {
        let samples = [top, (top + bottom) / 2, bottom]
        switch self {
        case let .circle(center, radius, margin):
            let reach = radius + margin
            var spans: [ClosedRange<CGFloat>] = []
            for y in samples where abs(y - center.y) <= reach {
                let dy = y - center.y
                let half = (reach * reach - dy * dy).squareRoot()
                spans.append((center.x - half)...(center.x + half))
            }
            return TextSpans.union(spans)
        case let .rect(rect, margin):
            guard bottom >= rect.minY - margin, top <= rect.maxY + margin else { return [] }
            return [(rect.minX - margin)...(rect.maxX + margin)]
        case let .polygon(points, margin):
            var spans: [ClosedRange<CGFloat>] = []
            for y in samples {
                for span in TextObstacle.scanline(points, y: y) {
                    spans.append((span.lowerBound - margin)...(span.upperBound + margin))
                }
            }
            return TextSpans.union(spans)
        }
    }

    /// Even-odd crossings of a horizontal line with the polygon's edges, paired into spans.
    /// The margin is applied horizontally, which is exact for vertical edges and close for the rest.
    private static func scanline(_ points: [CGPoint], y: CGFloat) -> [ClosedRange<CGFloat>] {
        var xs: [CGFloat] = []
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            guard (a.y <= y) != (b.y <= y) else { continue }
            xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
        }
        xs.sort()
        var spans: [ClosedRange<CGFloat>] = []
        var k = 0
        while k + 1 < xs.count {
            spans.append(xs[k]...xs[k + 1])
            k += 2
        }
        return spans
    }
}
