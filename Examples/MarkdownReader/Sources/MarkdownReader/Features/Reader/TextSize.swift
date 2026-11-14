import SwiftUI

enum TextSize: CaseIterable, Sendable, Hashable {
    case small, standard, large, larger, largest

    var title: String {
        switch self {
        case .small: return Strings.TextSizeOption.small
        case .standard: return Strings.TextSizeOption.standard
        case .large: return Strings.TextSizeOption.large
        case .larger: return Strings.TextSizeOption.larger
        case .largest: return Strings.TextSizeOption.largest
        }
    }

    /// The reader scales its own text through Dynamic Type, so the system's
    /// text styles (and their bold and italic variants) follow the choice.
    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .standard: return .large
        case .large: return .xLarge
        case .larger: return .xxLarge
        case .largest: return .accessibility1
        }
    }
}
