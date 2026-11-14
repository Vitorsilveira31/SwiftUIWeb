import SwiftUI

/// The series as an open path across a rectangle: the first value at the left
/// edge, the last at the right, 0 at the bottom and 1 at the top.
struct SeriesLine: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(
                x: rect.minX + CGFloat(index) * step,
                y: rect.minY + (1 - CGFloat(value)) * rect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
