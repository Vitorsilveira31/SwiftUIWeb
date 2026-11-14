struct Notice: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let body: String
    let time: String
    let destination: Destination
}
