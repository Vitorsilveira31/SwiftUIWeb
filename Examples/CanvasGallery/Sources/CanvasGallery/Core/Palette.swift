import SwiftUI

/// Colours shared by the fixtures: the ink, hex and CSS-style hsl colours, and gradient stops.
@MainActor
enum Palette {
    static let ink = hex(0x0f172a)

    static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        ).opacity(alpha)
    }

    /// CSS `hsl()`: hue in degrees, saturation and lightness as fractions.
    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Color {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue.truncatingRemainder(dividingBy: 360) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        var rgb = (r: 0.0, g: 0.0, b: 0.0)
        switch sector {
        case 0..<1: rgb = (chroma, second, 0)
        case 1..<2: rgb = (second, chroma, 0)
        case 2..<3: rgb = (0, chroma, second)
        case 3..<4: rgb = (0, second, chroma)
        case 4..<5: rgb = (second, 0, chroma)
        default: rgb = (chroma, 0, second)
        }
        let m = lightness - chroma / 2
        return Color(red: rgb.r + m, green: rgb.g + m, blue: rgb.b + m)
    }

    static func gradient(_ stops: [(Double, Color)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0) })
    }
}
