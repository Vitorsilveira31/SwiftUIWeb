/// The five pages of the gallery and the fixtures each one shows.
enum GalleryPage: Int, CaseIterable, Identifiable, Sendable {
    case shapes = 1, paint, sequences, text, pictures

    var id: Int { rawValue }

    var fixtures: [Fixture] {
        switch self {
        case .shapes: [.arc, .caps, .dash, .arcto, .roundrect, .ellipse, .transform, .kept]
        case .paint: [.linear, .radial, .alpha, .composite, .clip, .clear, .bitmap]
        case .sequences: [.accumulate, .stack, .reset, .throwing, .resize]
        case .text: [.textalign, .baseline, .textstyle, .textmeasure, .textrtl]
        case .pictures: [.image, .pattern, .conic, .path2d, .shadow, .extent, .pixels]
        }
    }
}
