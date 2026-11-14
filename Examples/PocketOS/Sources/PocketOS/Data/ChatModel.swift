// The assistant's models. None is a network choice here: each sets how fast the
// scripted answer streams, so the Settings picker changes something visible.
enum ChatModel: String, CaseIterable, Identifiable, Sendable {
    case quick, balanced, thorough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: Strings.Settings.quick
        case .balanced: Strings.Settings.balanced
        case .thorough: Strings.Settings.thorough
        }
    }

    var pace: Duration {
        switch self {
        case .quick: .milliseconds(35)
        case .balanced: .milliseconds(70)
        case .thorough: .milliseconds(120)
        }
    }
}
