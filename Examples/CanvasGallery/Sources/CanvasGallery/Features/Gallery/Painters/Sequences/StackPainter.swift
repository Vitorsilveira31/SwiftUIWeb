import SwiftUI

/// Save and restore: step 0 saves the state and translates; step 1 draws inside that state and then
/// restores it. The saved copy of the context is what the restore brings back.
@MainActor
enum StackPainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        var working = context
        var fill = Color.black
        var saved: (GraphicsContext, Color)?
        for s in 0...step {
            if s == 0 {
                saved = (working, fill)
                fill = Palette.hex(0xef4444)
                working.translateBy(x: 40, y: 0)
            }
            working.fill(
                Paths.rect(Double(10 + s * 12), Double(20 + s * 18), 30, 14),
                with: .color(fill)
            )
            if s == 1, let outer = saved {
                working = outer.0
                fill = outer.1
            }
        }
    }
}
