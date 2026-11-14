// The reference's fixed cities. "Current location" is a fixed position in this demo:
// there is no CoreLocation here, so it selects these coordinates.
struct CatalogCityRepository: CityRepository {
    static let current = CityVO(
        id: "current", name: Strings.Cities.currentLocation, region: Strings.Cities.fixedPosition,
        latitude: 38.7223, longitude: -9.1393)
    static let sanFrancisco = CityVO(
        id: "san-francisco", name: "San Francisco", region: "California, United States",
        latitude: 37.7749, longitude: -122.4194)
    static let london = CityVO(
        id: "london", name: "London", region: "England, United Kingdom",
        latitude: 51.5074, longitude: -0.1278)
    static let tokyo = CityVO(
        id: "tokyo", name: "Tokyo", region: "Japan",
        latitude: 35.6762, longitude: 139.6503)
    static let reykjavik = CityVO(
        id: "reykjavik", name: "Reykjavík", region: "Iceland",
        latitude: 64.1466, longitude: -21.9426)
    static let defaultCity = sanFrancisco

    var all: [CityVO] {
        [Self.current, Self.sanFrancisco, Self.london, Self.tokyo, Self.reykjavik]
    }

    var currentLocation: CityVO {
        Self.current
    }
}
