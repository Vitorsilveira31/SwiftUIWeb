import SwiftUI

// Two overlapping discs, one path: a union under the nonzero rule.
struct TwoDiscs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 62, y: 18, width: 32, height: 32))
        path.addEllipse(in: CGRect(x: 82, y: 32, width: 32, height: 32))
        return path
    }
}
