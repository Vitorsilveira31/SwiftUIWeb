import SwiftUI

/// A tile that grows with the step. Each size is a new canvas generation, so only the current step is
/// drawn, on a fresh context whose fill is the default black; only step 0 sets the purple fill.
@MainActor
enum ResizePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let fill = step == 0 ? Palette.hex(0x7c3aed) : Color.black
        let width = Double(size.width)
        let height = Double(size.height)
        context.fill(Paths.rect(4, 4, width - 8, 14), with: .color(fill))
        context.stroke(
            Paths.rect(0.5, 0.5, width - 1, height - 1),
            with: .color(.black), style: StrokeStyle(lineWidth: 1)
        )
    }
}
