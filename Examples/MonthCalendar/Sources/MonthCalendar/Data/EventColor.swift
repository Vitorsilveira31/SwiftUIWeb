import SwiftUI

enum EventColor: String, CaseIterable, Hashable, Sendable {
    case blue, green, orange, pink, purple

    var color: Color {
        switch self {
        case .blue: return Color.blue
        case .green: return Color.green
        case .orange: return Color.orange
        case .pink: return Color.pink
        case .purple: return Color.purple
        }
    }

    var title: String { rawValue.capitalized }
}
