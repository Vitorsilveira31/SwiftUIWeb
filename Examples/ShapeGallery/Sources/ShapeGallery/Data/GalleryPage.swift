// The ten pages of the gallery, numbered as the segmented control shows them.
enum GalleryPage: Int, CaseIterable, Identifiable {
    case one = 1, two, three, four, five, six, seven, eight, nine, ten

    var id: Int { rawValue }
    var label: String { String(rawValue) }
}
