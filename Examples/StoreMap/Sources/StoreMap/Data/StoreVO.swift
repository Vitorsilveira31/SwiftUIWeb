import MapKit

/// A store the map shows as a pin. Stores with `hasPickButton` also get a button above the map.
struct StoreVO: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let latitude: Double
    let longitude: Double
    let hasPickButton: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
