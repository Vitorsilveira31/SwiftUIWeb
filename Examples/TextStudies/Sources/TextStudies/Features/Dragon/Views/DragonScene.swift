import SwiftUI

/// The dragon's silhouette, placement and painter. The outline is both the ink and the exclusion.
@MainActor
enum DragonScene {
    /// Design units: the silhouette is drawn in a 400 by 250 box, facing left.
    static let design = CGSize(width: 400, height: 250)
    static let outline: [CGPoint] = [
        CGPoint(x: 12, y: 110), CGPoint(x: 40, y: 96), CGPoint(x: 62, y: 84), CGPoint(x: 80, y: 60),
        CGPoint(x: 88, y: 80), CGPoint(x: 126, y: 86), CGPoint(x: 150, y: 92), CGPoint(x: 168, y: 78),
        CGPoint(x: 196, y: 62), CGPoint(x: 232, y: 46), CGPoint(x: 262, y: 34), CGPoint(x: 300, y: 30),
        CGPoint(x: 332, y: 44), CGPoint(x: 358, y: 66), CGPoint(x: 378, y: 88), CGPoint(x: 398, y: 104),
        CGPoint(x: 384, y: 116), CGPoint(x: 360, y: 110), CGPoint(x: 338, y: 124), CGPoint(x: 324, y: 146),
        CGPoint(x: 332, y: 182), CGPoint(x: 312, y: 190), CGPoint(x: 300, y: 166), CGPoint(x: 278, y: 158),
        CGPoint(x: 262, y: 178), CGPoint(x: 256, y: 200), CGPoint(x: 236, y: 202), CGPoint(x: 232, y: 168),
        CGPoint(x: 208, y: 160), CGPoint(x: 182, y: 166), CGPoint(x: 176, y: 196), CGPoint(x: 156, y: 198),
        CGPoint(x: 152, y: 166), CGPoint(x: 128, y: 150), CGPoint(x: 96, y: 134), CGPoint(x: 62, y: 128),
        CGPoint(x: 32, y: 124),
    ]
    static let eye = CGPoint(x: 58, y: 96)
    static let dropCapBox = CGRect(x: 0, y: 0, width: 62, height: 72)

    static func scale(for width: CGFloat) -> CGFloat {
        min(1, max(0.5, (width - 24) / design.width))
    }

    /// Where the dragon is drawn: centred at rest, moved by the reader, kept on the page.
    static func frame(in size: CGSize, offset: CGSize) -> CGRect {
        let s = scale(for: size.width)
        let w = design.width * s
        let h = design.height * s
        let x = min(max((size.width - w) / 2 + offset.width, 0), max(0, size.width - w))
        let y = min(max(120 * s + offset.height, 0), max(0, size.height - h))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func draw(
        into context: inout GraphicsContext,
        size: CGSize,
        offset: CGSize,
        widths: WidthCache,
        words: [String],
        dropCap: String
    ) {
        let s = scale(for: size.width)
        let box = frame(in: size, offset: offset)
        let points = outline.map { CGPoint(x: box.minX + $0.x * s, y: box.minY + $0.y * s) }
        let lineHeight: CGFloat = 26
        // Text flows in a box inset by 12 pt, so the flow works in coordinates shifted by that inset.
        let inset: CGFloat = 12
        let flowPoints = points.map { CGPoint(x: $0.x - inset, y: $0.y - inset) }

        let page = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10)
        context.fill(page, with: .color(Color.gray.opacity(0.1)))

        let obstacles: [TextObstacle] = [
            .polygon(flowPoints, margin: 12),
            .rect(dropCapBox, margin: 8),
        ]
        var wordWidths: [CGFloat] = []
        wordWidths.reserveCapacity(words.count)
        for word in words {
            wordWidths.append(widths.width(word, in: &context))
        }
        let input = LineBreakInput(
            widths: wordWidths,
            breaks: [Bool](repeating: false, count: words.count),
            space: widths.width(" ", in: &context),
            lineHeight: lineHeight,
            columns: 1,
            columnWidth: size.width - 24,
            gap: 0,
            obstacles: obstacles)
        let origins = LineBreaker.fill(input, bands: Int((size.height - 24) / lineHeight)).origins
        for (index, origin) in origins.enumerated() {
            let resolved = context.resolve(Text(words[index]).font(TextFonts.article).foregroundStyle(.primary))
            context.draw(resolved, at: CGPoint(x: origin.x + 12, y: origin.y + 12), anchor: .topLeading)
        }

        let cap = context.resolve(
            Text(dropCap)
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(Color(red: 0.55, green: 0.18, blue: 0.12)))
        context.draw(cap, at: CGPoint(x: 12, y: 12), anchor: .topLeading)

        var body = Path()
        body.addLines(points)
        body.closeSubpath()
        context.fill(body, with: .color(Color(red: 0.25, green: 0.42, blue: 0.31)))
        let eyeCenter = CGPoint(x: box.minX + eye.x * s, y: box.minY + eye.y * s)
        let eyeRadius = 6 * s
        context.fill(
            Path(ellipseIn: CGRect(x: eyeCenter.x - eyeRadius, y: eyeCenter.y - eyeRadius,
                                   width: eyeRadius * 2, height: eyeRadius * 2)),
            with: .color(Color(red: 0.95, green: 0.76, blue: 0.31)))
    }
}
