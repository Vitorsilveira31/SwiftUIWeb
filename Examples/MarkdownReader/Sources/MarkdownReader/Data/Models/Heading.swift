struct Heading: Identifiable, Sendable, Equatable {
    /// The id of the heading's block, which is also where a contents jump lands.
    let id: Int
    let level: Int
    let title: String
}
