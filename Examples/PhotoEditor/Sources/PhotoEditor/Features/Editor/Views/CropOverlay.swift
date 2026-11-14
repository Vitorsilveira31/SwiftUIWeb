import SwiftUI

/// The crop overlay: the photo outside the crop dimmed (even-odd, so the crop is a hole), its thirds, and
/// corner brackets marking the handles.
struct CropOverlay: View {
    let crop: Crop

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(
                x: crop.x * size.width,
                y: crop.y * size.height,
                width: crop.width * size.width,
                height: crop.height * size.height
            )

            var dim = Path(CGRect(origin: .zero, size: size))
            dim.addRect(rect)
            context.fill(dim, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))

            var thirds = Path()
            for step in 1...2 {
                let t = CGFloat(step) / 3
                thirds.move(to: CGPoint(x: rect.minX + rect.width * t, y: rect.minY))
                thirds.addLine(to: CGPoint(x: rect.minX + rect.width * t, y: rect.maxY))
                thirds.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * t))
                thirds.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * t))
            }
            context.stroke(thirds, with: .color(.white.opacity(0.35)), lineWidth: 1)
            context.stroke(Path(rect), with: .color(.white.opacity(0.95)), lineWidth: 1.5)

            var brackets = Path()
            let arm = min(22, rect.width / 3, rect.height / 3)
            for (x, dx) in [(rect.minX, arm), (rect.maxX, -arm)] {
                for (y, dy) in [(rect.minY, arm), (rect.maxY, -arm)] {
                    brackets.move(to: CGPoint(x: x + dx, y: y))
                    brackets.addLine(to: CGPoint(x: x, y: y))
                    brackets.addLine(to: CGPoint(x: x, y: y + dy))
                }
            }
            context.stroke(brackets, with: .color(.white), lineWidth: 4)
        }
    }
}
