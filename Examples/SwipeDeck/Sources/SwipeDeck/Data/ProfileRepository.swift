/// Where the deck's people come from. The screen only needs the list, in deck order.
protocol ProfileRepository {
    func profiles() -> [Profile]
}
