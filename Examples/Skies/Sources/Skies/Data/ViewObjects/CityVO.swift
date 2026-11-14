struct CityVO: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let region: String
    let latitude: Double
    let longitude: Double
}
