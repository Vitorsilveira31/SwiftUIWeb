/// The four sample stores of the demo.
struct SampleStoreRepository: StoreRepository {
    func stores() -> [StoreVO] {
        [
            StoreVO(id: "ferry", title: "Ferry Building", latitude: 37.7955, longitude: -122.3937, hasPickButton: true),
            StoreVO(id: "coit", title: "Coit Tower", latitude: 37.8024, longitude: -122.4058, hasPickButton: true),
            StoreVO(id: "union", title: "Union Square", latitude: 37.788, longitude: -122.4075, hasPickButton: true),
            // The fourth store has a pin but no button.
            StoreVO(id: "chinatown", title: "Dragon Gate", latitude: 37.7941, longitude: -122.4078, hasPickButton: false),
        ]
    }
}
