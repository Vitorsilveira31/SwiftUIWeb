/// A slider's filter, with the range it runs over.
enum Adjustment: String, CaseIterable, Identifiable, Sendable {
    case brightness, contrast, saturation, hue, blur, grayscale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brightness: Strings.Adjustment.brightness
        case .contrast: Strings.Adjustment.contrast
        case .saturation: Strings.Adjustment.saturation
        case .hue: Strings.Adjustment.hue
        case .blur: Strings.Adjustment.blur
        case .grayscale: Strings.Adjustment.grayscale
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: -0.5...0.5
        case .contrast, .saturation: 0...2
        case .hue: -180...180
        case .blur: 0...10
        case .grayscale: 0...1
        }
    }

    // A stored WritableKeyPath would be the usual way to say which field a slider edits, but Embedded Swift (the
    // browser build) has no key path values, so the field is read and written through these two functions.
    func value(in edit: Edit) -> Double {
        switch self {
        case .brightness: edit.brightness
        case .contrast: edit.contrast
        case .saturation: edit.saturation
        case .hue: edit.hue
        case .blur: edit.blur
        case .grayscale: edit.grayscale
        }
    }

    func set(_ value: Double, in edit: inout Edit) {
        switch self {
        case .brightness: edit.brightness = value
        case .contrast: edit.contrast = value
        case .saturation: edit.saturation = value
        case .hue: edit.hue = value
        case .blur: edit.blur = value
        case .grayscale: edit.grayscale = value
        }
    }
}
