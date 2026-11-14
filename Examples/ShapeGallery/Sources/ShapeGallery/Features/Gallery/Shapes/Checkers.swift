import SwiftUI

// A checker of two squares per cell, `columns` by `rows` cells from `origin`.
struct Checkers: Shape {
    let origin: CGPoint
    let cell: CGFloat
    let columns: Int
    let rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 0..<rows {
            for column in 0..<columns {
                let x = origin.x + CGFloat(column) * cell
                let y = origin.y + CGFloat(row) * cell
                path.addRect(CGRect(x: x, y: y, width: cell / 2, height: cell / 2))
                path.addRect(CGRect(x: x + cell / 2, y: y + cell / 2, width: cell / 2, height: cell / 2))
            }
        }
        return path
    }
}
