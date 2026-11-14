import SwiftUI

extension Color {
    // Content hues are fixed on purpose: a picture must look the same in light and dark.
    init(hex value: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }
}
