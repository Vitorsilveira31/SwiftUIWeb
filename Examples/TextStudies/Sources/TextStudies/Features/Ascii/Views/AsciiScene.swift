import SwiftUI

/// The ASCII sphere's painter: a ramp of characters picked per cell from the lit shading.
@MainActor
enum AsciiScene {
    static let rows = 32
    static let rowHeight: CGFloat = 13
    static let width: CGFloat = 340
    /// Lightest to darkest.
    static let ramp: [Character] = Array(" .:-=+*#%@")

    static func draw(
        into context: inout GraphicsContext,
        face: AsciiFace,
        seconds: Double,
        proportional: WidthCache,
        monospaced: WidthCache
    ) {
        let height = CGFloat(rows) * rowHeight
        let font = face == .monospaced ? TextFonts.mono : TextFonts.glyph
        let monoAdvance = monospaced.width("M", in: &context)
        var rampTotal: CGFloat = 0
        for character in ramp {
            rampTotal += proportional.width(String(character), in: &context)
        }
        let gridAdvance = rampTotal / CGFloat(ramp.count)

        for row in 0..<rows {
            let y = CGFloat(row) * rowHeight
            var pen: CGFloat = 0
            var index = 0
            while pen < width && index < 200 {
                // Sample where the glyph will be drawn, so measured rows sample the real picture.
                let sampleX: CGFloat
                switch face {
                case .measured: sampleX = pen
                case .grid: sampleX = CGFloat(index) * gridAdvance
                case .monospaced: sampleX = CGFloat(index) * monoAdvance
                }
                let glyph = pick(x: sampleX + 2, y: y + rowHeight / 2, height: height, seconds: seconds)
                let letter = String(glyph)
                let advance: CGFloat
                switch face {
                case .measured: advance = proportional.width(letter, in: &context)
                case .grid: advance = gridAdvance
                case .monospaced: advance = monoAdvance
                }
                let resolved = context.resolve(Text(letter).font(font).foregroundStyle(.primary))
                context.draw(resolved, at: CGPoint(x: pen, y: y), anchor: .topLeading)
                pen += max(advance, 0.5)
                index += 1
            }
        }
    }

    static func pick(x: CGFloat, y: CGFloat, height: CGFloat, seconds: Double) -> Character {
        let darkness = shade(x: x, y: y, height: height, seconds: seconds)
        let index = Int((min(max(darkness, 0), 1) * CGFloat(ramp.count - 1)).rounded())
        return ramp[index]
    }

    /// Ink darkness at a point: the ring behind and over the sphere, and the sphere's lit side.
    static func shade(x: CGFloat, y: CGFloat, height: CGFloat, seconds: Double) -> CGFloat {
        let cx = width / 2
        let cy = height * 0.47
        let r = height * 0.34
        let dx = x - cx
        let dy = y - cy
        let ringA = width * 0.43
        let ringB = height * 0.115
        let e = dx * dx / (ringA * ringA) + dy * dy / (ringB * ringB)
        let inSphere = dx * dx + dy * dy < r * r
        if e >= 0.66 && e <= 1 && (dy > 0 || !inSphere) {
            let angle = CGFloat(atan2(Double(dy), Double(dx)))
            return 0.45 + 0.2 * CGFloat(sin(Double(angle)))
        }
        guard inSphere else { return 0 }

        let theta = seconds * 0.7
        let lx = CGFloat(cos(theta))
        let ly: CGFloat = -0.55
        let lz: CGFloat = 0.7
        let norm = (lx * lx + ly * ly + lz * lz).squareRoot()
        let nz = (r * r - dx * dx - dy * dy).squareRoot() / r
        let lit = max(0, (dx / r) * (lx / norm) + (dy / r) * (ly / norm) + nz * (lz / norm))
        let rim = pow(1 - nz, 3) * 0.25
        return min(1, max(0, 1 - (0.06 + 0.94 * lit) + rim))
    }
}
