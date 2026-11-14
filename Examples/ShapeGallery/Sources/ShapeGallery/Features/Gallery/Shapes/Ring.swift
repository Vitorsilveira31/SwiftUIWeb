import SwiftUI

// A disc of radius 18 with a hole of radius 10, the hole wound the other way.
struct Ring: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: 38, y: 40), radius: 18, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        path.addArc(center: CGPoint(x: 38, y: 40), radius: 10, startAngle: .zero, endAngle: .degrees(360), clockwise: true)
        return path
    }
}
