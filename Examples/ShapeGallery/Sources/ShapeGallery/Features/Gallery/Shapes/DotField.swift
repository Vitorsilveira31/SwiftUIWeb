import SwiftUI

// A field of dots, one per 10 x 10 cell of user space, centred in each cell.
struct DotField: Shape {
    let region: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var row: CGFloat = 0
        while row * 10 < region.maxY {
            var column: CGFloat = 0
            while column * 10 < region.maxX {
                let centre = CGPoint(x: column * 10 + 5, y: row * 10 + 5)
                if region.contains(centre) {
                    path.addEllipse(in: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6))
                }
                column += 1
            }
            row += 1
        }
        return path
    }
}
