struct Article: Identifiable, Hashable, Sendable {
    let id: String
    let section: String
    let minutes: Int
    let author: String
    let posted: String
    let title: String
    let deck: String
    let pull: String
    let body: [String]
}
