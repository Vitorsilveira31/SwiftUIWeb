// Where the app gets its cities: the list the picker filters, and the current location.
protocol CityRepository: Sendable {
    var all: [CityVO] { get }
    var currentLocation: CityVO { get }
}
