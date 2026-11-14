import SwiftUI

/// An exclusion shape in the coordinate space of its text box. Circles, rectangles and polygons
/// are all reduced to horizontal spans per line, which is all the line breaker needs.
struct WrapExclusion: Identifiable, Sendable {
    enum Outline: Sendable {
        case circle(center: CGPoint, radius: CGFloat)
        case polygon([CGPoint])
        case rect(CGRect)
    }

    let id: String
    let outline: Outline
    /// Clearance kept between the text and the shape, like CSS shape-margin.
    let margin: CGFloat
    /// A drawn shape; nil for an invisible exclusion such as a drop-cap box.
    var tint: WrapTint? = nil
    /// Text drawn inside a rectangle: a drop cap or a pull quotation.
    var caption: WrapCaption? = nil

    static func disc(_ id: String, center: CGPoint, radius: CGFloat, margin: CGFloat, tint: WrapTint) -> WrapExclusion {
        WrapExclusion(id: id, outline: .circle(center: center, radius: radius), margin: margin, tint: tint)
    }

    static func polygon(_ id: String, _ points: [CGPoint], margin: CGFloat, tint: WrapTint) -> WrapExclusion {
        WrapExclusion(id: id, outline: .polygon(points), margin: margin, tint: tint)
    }

    /// Horizontal spans this shape covers on the line at `y`, grown by the margin.
    func intervals(at y: CGFloat) -> [Range<CGFloat>] {
        switch outline {
        case .circle(let center, let radius):
            let reach = radius + margin
            let dy = y - center.y
            guard abs(dy) < reach else { return [] }
            let half = (reach * reach - dy * dy).squareRoot()
            return [(center.x - half)..<(center.x + half)]
        case .rect(let rect):
            guard y >= rect.minY - margin, y <= rect.maxY + margin else { return [] }
            return [(rect.minX - margin)..<(rect.maxX + margin)]
        case .polygon(let points):
            // Even-odd crossings of the horizontal line give the inside spans.
            var xs: [CGFloat] = []
            for i in points.indices {
                let p = points[i], q = points[(i + 1) % points.count]
                if (p.y <= y) != (q.y <= y) {
                    xs.append(p.x + (y - p.y) * (q.x - p.x) / (q.y - p.y))
                }
            }
            xs.sort()
            return stride(from: 0, to: xs.count - 1, by: 2).map { (xs[$0] - margin)..<(xs[$0 + 1] + margin) }
        }
    }
}
