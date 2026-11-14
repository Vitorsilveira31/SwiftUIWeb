/// Where the Stores screen gets its stores.
protocol StoreRepository: Sendable {
    func stores() -> [StoreVO]
}
