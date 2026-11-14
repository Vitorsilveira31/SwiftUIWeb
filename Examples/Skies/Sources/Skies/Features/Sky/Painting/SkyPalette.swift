import SwiftUI

typealias SkyRGB = (r: Double, g: Double, b: Double)

// The sky's colours. Each painter blends these by the same inputs as the reference's shader.
enum SkyPalette {
    static let nightTop: SkyRGB = (0.015, 0.030, 0.075)
    static let nightLow: SkyRGB = (0.065, 0.110, 0.180)
    static let dayTop: SkyRGB = (0.035, 0.160, 0.310)
    static let dayLow: SkyRGB = (0.340, 0.570, 0.650)
    static let dusk: SkyRGB = (0.860, 0.400, 0.260)
    static let storm: SkyRGB = (0.105, 0.160, 0.210)
    static let cloudNight: SkyRGB = (0.130, 0.160, 0.260)
    static let cloudDay: SkyRGB = (0.920, 0.940, 0.950)
    static let hillNight: SkyRGB = (0.025, 0.060, 0.075)
    static let hillDay: SkyRGB = (0.080, 0.180, 0.220)

    static func mix(_ a: SkyRGB, _ b: SkyRGB, _ t: Double) -> SkyRGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    static func color(_ c: SkyRGB) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }
}
