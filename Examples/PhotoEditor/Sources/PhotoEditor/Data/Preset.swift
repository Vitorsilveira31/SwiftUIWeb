/// A preset filter: a look that sets several adjustments at once.
enum Preset: String, CaseIterable, Identifiable, Sendable {
    case original, vivid, mono, fade, dream, cool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: Strings.Preset.original
        case .vivid: Strings.Preset.vivid
        case .mono: Strings.Preset.mono
        case .fade: Strings.Preset.fade
        case .dream: Strings.Preset.dream
        case .cool: Strings.Preset.cool
        }
    }

    var look: Edit {
        switch self {
        case .original: Edit()
        case .vivid: Edit(brightness: 0.05, contrast: 1.15, saturation: 1.6)
        case .mono: Edit(contrast: 1.1, grayscale: 1)
        case .fade: Edit(brightness: 0.08, contrast: 0.8, saturation: 0.6)
        case .dream: Edit(brightness: 0.06, contrast: 0.95, saturation: 0.85, blur: 2.5)
        case .cool: Edit(brightness: 0.02, saturation: 1.1, hue: -25)
        }
    }
}
