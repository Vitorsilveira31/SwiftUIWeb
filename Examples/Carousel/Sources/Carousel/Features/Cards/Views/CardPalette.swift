import SwiftUI

/// Fixed content hues. Card labels are white on these in either scheme.
enum CardPalette {
    static let hues: [Color] = [
        Color(red: 180 / 255, green: 83 / 255, blue: 9 / 255),
        Color(red: 67 / 255, green: 56 / 255, blue: 202 / 255),
        Color(red: 4 / 255, green: 120 / 255, blue: 87 / 255),
        Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255),
        Color(red: 3 / 255, green: 105 / 255, blue: 161 / 255),
        Color(red: 126 / 255, green: 34 / 255, blue: 206 / 255),
    ]

    static func color(_ hue: Int) -> Color {
        hues[hue]
    }
}
