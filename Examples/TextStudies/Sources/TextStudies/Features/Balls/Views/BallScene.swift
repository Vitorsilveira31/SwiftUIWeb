import SwiftUI

/// The balls' geometry and painter: positions from the clock, text flowed around them.
@MainActor
enum BallScene {
    struct Ball: Sendable {
        let radius: CGFloat
        /// Points per millisecond.
        let speedX: CGFloat
        let speedY: CGFloat
        let startX: CGFloat
        let startY: CGFloat
        let color: Color
    }

    static let balls: [Ball] = [
        Ball(radius: 58, speedX: 0.061, speedY: 0.043, startX: 40, startY: 30,
             color: Color(red: 0.76, green: 0.38, blue: 0.25)),
        Ball(radius: 40, speedX: -0.047, speedY: 0.071, startX: 360, startY: 200,
             color: Color(red: 0.31, green: 0.49, blue: 0.42)),
        Ball(radius: 30, speedX: 0.083, speedY: -0.052, startX: 200, startY: 120,
             color: Color(red: 0.72, green: 0.60, blue: 0.28)),
    ]

    static func origin(of ball: Ball, elapsed: CGFloat, in size: CGSize) -> CGPoint {
        CGPoint(
            x: bounce(ball.startX + ball.speedX * elapsed, limit: size.width - 2 * ball.radius),
            y: bounce(ball.startY + ball.speedY * elapsed, limit: size.height - 2 * ball.radius))
    }

    /// A triangle wave between 0 and `limit`: a bounce that needs no history.
    static func bounce(_ position: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let period = 2 * limit
        var m = position.truncatingRemainder(dividingBy: period)
        if m < 0 { m += period }
        return m > limit ? period - m : m
    }

    static func draw(
        into context: inout GraphicsContext,
        size: CGSize,
        elapsed: CGFloat,
        widths: WidthCache,
        words: [String]
    ) {
        let lineHeight: CGFloat = 26
        let positions = balls.map { origin(of: $0, elapsed: elapsed, in: size) }
        var obstacles: [TextObstacle] = []
        for (ball, origin) in zip(balls, positions) {
            let center = CGPoint(x: origin.x + ball.radius, y: origin.y + ball.radius)
            obstacles.append(.circle(center: center, radius: ball.radius, margin: 12))
        }

        var wordWidths: [CGFloat] = []
        wordWidths.reserveCapacity(words.count)
        for word in words {
            wordWidths.append(widths.width(word, in: &context))
        }
        let space = widths.width(" ", in: &context)
        let input = LineBreakInput(
            widths: wordWidths,
            breaks: [Bool](repeating: false, count: words.count),
            space: space,
            lineHeight: lineHeight,
            columns: 1,
            columnWidth: size.width,
            gap: 0,
            obstacles: obstacles)
        let origins = LineBreaker.fill(input, bands: Int(size.height / lineHeight)).origins
        for (index, origin) in origins.enumerated() {
            let resolved = context.resolve(Text(words[index]).font(TextFonts.body).foregroundStyle(.primary))
            context.draw(resolved, at: origin, anchor: .topLeading)
        }

        for (ball, origin) in zip(balls, positions) {
            let rect = CGRect(origin: origin, size: CGSize(width: ball.radius * 2, height: ball.radius * 2))
            context.fill(Path(ellipseIn: rect), with: .color(ball.color))
        }
    }
}
