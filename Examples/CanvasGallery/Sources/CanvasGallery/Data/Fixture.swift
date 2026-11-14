import SwiftUI

/// The 32 fixtures, in the order the five pages show them. Each one is a tile captioned with its
/// `fx-*` identifier and drawn by the painter named after it.
enum Fixture: String, CaseIterable, Identifiable, Sendable {
    // Page 1: shapes and paths.
    case arc, caps, dash, arcto, roundrect, ellipse, transform, kept
    // Page 2: paint.
    case linear, radial, alpha, composite, clip, clear, bitmap
    // Page 3: sequences, redrawn from the step counter.
    case accumulate, stack, reset, throwing = "throws", resize
    // Page 4: text.
    case textalign, baseline, textstyle, textmeasure, textrtl
    // Page 5: pictures, shadows and pixels.
    case image, pattern, conic, path2d, shadow, extent, pixels

    var id: String { rawValue }
    var identifier: String { "fx-\(rawValue)" }
    var caption: String { identifier }

    /// The resize tile grows with the step; every other tile is the reference's 150 by 100.
    @MainActor
    func width(step: Int) -> CGFloat {
        self == .resize ? CGFloat(90 + step * 20) : TileMetrics.width
    }

    /// The ink of the tile, or the colour the reference sets on its text canvas.
    @MainActor
    var foreground: Color {
        self == .textrtl ? Palette.hex(0xbe185d) : Palette.ink
    }

    @MainActor
    func draw(into context: inout GraphicsContext, size: CGSize, step: Int) {
        switch self {
        case .arc: ArcPainter.draw(in: &context, size: size, step: step)
        case .caps: CapsPainter.draw(in: &context, size: size, step: step)
        case .dash: DashPainter.draw(in: &context, size: size, step: step)
        case .arcto: ArcToPainter.draw(in: &context, size: size, step: step)
        case .roundrect: RoundRectPainter.draw(in: &context, size: size, step: step)
        case .ellipse: EllipsePainter.draw(in: &context, size: size, step: step)
        case .transform: TransformPainter.draw(in: &context, size: size, step: step)
        case .kept: KeptPainter.draw(in: &context, size: size, step: step)
        case .linear: LinearPainter.draw(in: &context, size: size, step: step)
        case .radial: RadialPainter.draw(in: &context, size: size, step: step)
        case .alpha: AlphaPainter.draw(in: &context, size: size, step: step)
        case .composite: CompositePainter.draw(in: &context, size: size, step: step)
        case .clip: ClipPainter.draw(in: &context, size: size, step: step)
        case .clear: ClearPainter.draw(in: &context, size: size, step: step)
        case .bitmap: BitmapPainter.draw(in: &context, size: size, step: step)
        case .accumulate: AccumulatePainter.draw(in: &context, size: size, step: step)
        case .stack: StackPainter.draw(in: &context, size: size, step: step)
        case .reset: ResetPainter.draw(in: &context, size: size, step: step)
        case .throwing: ThrowingPainter.draw(in: &context, size: size, step: step)
        case .resize: ResizePainter.draw(in: &context, size: size, step: step)
        case .textalign: TextAlignPainter.draw(in: &context, size: size, step: step)
        case .baseline: BaselinePainter.draw(in: &context, size: size, step: step)
        case .textstyle: TextStylePainter.draw(in: &context, size: size, step: step)
        case .textmeasure: TextMeasurePainter.draw(in: &context, size: size, step: step)
        case .textrtl: TextRTLPainter.draw(in: &context, size: size, step: step)
        case .image: ImagePainter.draw(in: &context, size: size, step: step)
        case .pattern: PatternPainter.draw(in: &context, size: size, step: step)
        case .conic: ConicPainter.draw(in: &context, size: size, step: step)
        case .path2d: Path2DPainter.draw(in: &context, size: size, step: step)
        case .shadow: ShadowPainter.draw(in: &context, size: size, step: step)
        case .extent: ExtentPainter.draw(in: &context, size: size, step: step)
        case .pixels: PixelsPainter.draw(in: &context, size: size, step: step)
        }
    }
}
