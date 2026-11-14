import SwiftUI

/// Italic, a gradient fill, a squeezed run, letter spacing and a rotated run. SwiftUI text has no
/// outline stroke, so the reference's "Stroke" run is filled.
@MainActor
enum TextStylePainter {
    static func draw(in context: inout GraphicsContext, size: CGSize, step: Int) {
        let anchor = UnitPoint(x: 0, y: CanvasText.baselineAnchor)
        CanvasText.draw(
            &context, "Italic", font: .system(size: 16).italic(), color: Palette.hex(0x7c3aed),
            at: CGPoint(x: 6, y: 20), anchor: anchor
        )
        CanvasText.draw(
            &context, "Stroke", font: .system(size: 22, weight: .bold), color: Palette.ink,
            at: CGPoint(x: 70, y: 22), anchor: anchor
        )

        var gradient = context.resolve(Text("Gradient").font(.system(size: 24, weight: .bold)))
        gradient.shading = .linearGradient(
            Palette.gradient([(0, Palette.hex(0xef4444)), (1, Palette.hex(0x2563eb))]),
            startPoint: CGPoint(x: 6, y: 0), endPoint: CGPoint(x: 140, y: 0)
        )
        context.draw(gradient, at: CGPoint(x: 6, y: 52), anchor: anchor)

        // maxWidth 60: the run is scaled down horizontally to fit.
        var squeezed = context.resolve(Text("Squeezed into sixty").font(.system(size: 16)))
        squeezed.shading = .color(Palette.hex(0x16a34a))
        let natural = squeezed.measure(in: CanvasText.unbounded).width
        var fitted = context
        fitted.translateBy(x: 6, y: 74)
        fitted.scaleBy(x: min(1, 60 / natural), y: 1)
        fitted.draw(squeezed, at: .zero, anchor: anchor)

        // letterSpacing 3px is tracking on the text.
        var spaced = context.resolve(Text("spaced").font(.system(size: 16)).tracking(3))
        spaced.shading = .color(Palette.ink)
        context.draw(spaced, at: CGPoint(x: 72, y: 74), anchor: anchor)

        var turned = context
        turned.translateBy(x: 20, y: 92)
        turned.rotate(by: .radians(-0.12))
        CanvasText.draw(
            &turned, "rotated 12°", font: .system(size: 16), color: Palette.hex(0xb45309),
            at: .zero, anchor: anchor
        )
    }
}
