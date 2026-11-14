/// Where the market list's coins come from. The screen depends on this
/// protocol only, so the sample data can be replaced by a live source.
protocol CoinRepository: Sendable {
    func coins(version: Int) -> [CoinVO]
}
