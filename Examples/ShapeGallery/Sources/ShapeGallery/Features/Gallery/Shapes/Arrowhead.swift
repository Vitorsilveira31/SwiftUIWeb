import SwiftUI

// A triangular head of `length` with its middle at `centre`, pointing along `direction`.
struct Arrowhead: Shape {
    let centre: CGPoint
    let direction: CGPoint
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = centre
        let half = length / 2
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let front = CGPoint(x: c.x + direction.x * half, y: c.y + direction.y * half)
        let back = CGPoint(x: c.x - direction.x * half, y: c.y - direction.y * half)
        var path = Path()
        path.move(to: front)
        path.addLine(to: CGPoint(x: back.x + normal.x * half, y: back.y + normal.y * half))
        path.addLine(to: CGPoint(x: back.x - normal.x * half, y: back.y - normal.y * half))
        path.closeSubpath()
        return path
    }
}
