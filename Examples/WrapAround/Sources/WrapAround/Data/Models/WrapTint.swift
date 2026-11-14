import SwiftUI

/// Content colours for the shapes. Mid-tones read on both paper colours.
enum WrapTint: Sendable {
    case terracotta, sage, ochre, teal, clay, slate, plum, rose

    var color: Color {
        switch self {
        case .terracotta: Color(red: 0.75, green: 0.41, blue: 0.29)
        case .sage: Color(red: 0.46, green: 0.58, blue: 0.51)
        case .ochre: Color(red: 0.77, green: 0.66, blue: 0.41)
        case .teal: Color(red: 0.28, green: 0.42, blue: 0.41)
        case .clay: Color(red: 0.65, green: 0.51, blue: 0.47)
        case .slate: Color(red: 0.53, green: 0.61, blue: 0.67)
        case .plum: Color(red: 0.53, green: 0.24, blue: 0.28)
        case .rose: Color(red: 0.71, green: 0.38, blue: 0.41)
        }
    }
}
