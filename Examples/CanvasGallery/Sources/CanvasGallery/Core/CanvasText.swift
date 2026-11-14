import SwiftUI

/// Text for the fixtures. Canvas draws text at a baseline; SwiftUI anchors a text box, so the
/// baseline is approximated by a vertical anchor on the box.
@MainActor
enum CanvasText {
    /// Large proposal for measuring text at its natural size.
    static let unbounded = CGSize(width: 10_000, height: 10_000)

    /// A box anchor at 0.8 of the height sits close to the Canvas baseline.
    static let baselineAnchor = 0.8

    /// Draws `string` with the box's `anchor` at `point`; returns the box size.
    @discardableResult
    static func draw(
        _ context: inout GraphicsContext, _ string: String, font: Font, color: Color,
        at point: CGPoint, anchor: UnitPoint
    ) -> CGSize {
        var resolved = context.resolve(Text(string).font(font))
        resolved.shading = .color(color)
        context.draw(resolved, at: point, anchor: anchor)
        return resolved.measure(in: unbounded)
    }
}
