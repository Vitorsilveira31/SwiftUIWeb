/// The sheets the editor opens over itself.
enum EditorSheet: String, Identifiable {
    case camera, recents, save, order

    var id: String { rawValue }
}
