/// The three ways the ASCII study can pick its glyph advances.
enum AsciiFace: String, CaseIterable, Identifiable {
    case monospaced, measured, grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monospaced: Strings.Ascii.monoTitle
        case .measured: Strings.Ascii.measuredTitle
        case .grid: Strings.Ascii.gridTitle
        }
    }

    var explanation: String {
        switch self {
        case .monospaced: Strings.Ascii.monoExplanation
        case .measured: Strings.Ascii.measuredExplanation
        case .grid: Strings.Ascii.gridExplanation
        }
    }
}
