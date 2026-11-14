import SwiftUI

// A compass rose with a ring that fills with the wind's speed. The forecast request
// carries no wind direction, so the rose names the points but does not point.
struct Compass: View {
    let speed: Double

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4
            let ring = Path(ellipseIn: CGRect(
                x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

            for tick in 0..<12 {
                let angle = Double(tick) * Double.pi / 6 - Double.pi / 2
                var mark = Path()
                let inner = radius - (tick % 3 == 0 ? 7 : 4)
                mark.move(to: CGPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner))
                mark.addLine(to: CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
                context.stroke(mark, with: .color(.secondary), lineWidth: 1)
            }

            let fraction = min(max(speed / 80, 0), 1)
            if fraction > 0 {
                var arc = Path()
                arc.addArc(
                    center: centre,
                    radius: radius - 3,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * fraction),
                    clockwise: false)
                context.stroke(arc, with: .color(.teal), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            for (index, letter) in Strings.Elements.compassPoints.enumerated() {
                let angle = Double(index) * Double.pi / 2 - Double.pi / 2
                let point = CGPoint(
                    x: centre.x + cos(angle) * (radius - 16),
                    y: centre.y + sin(angle) * (radius - 16))
                context.draw(Text(letter).font(.caption2.bold()).foregroundStyle(.secondary), at: point, anchor: .center)
            }
        }
        .accessibilityLabel(Strings.Elements.compass)
    }
}
