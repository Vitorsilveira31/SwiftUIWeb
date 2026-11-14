import CloneKit

/// What Stayly needs from the outside, in one place: a test builds it with doubles, the app with `live`.
struct StaylyDependencies {
  let loadStays: any LoadStaysUseCase
  let loadDetail: any LoadStayDetailUseCase
  let reserve: any ReserveStayUseCase

  static var live: StaylyDependencies {
    let client = PlaceholderClient()
    let stays = LiveStaysRepository(client: client)
    return StaylyDependencies(
      loadStays: DefaultLoadStaysUseCase(repository: stays),
      loadDetail: DefaultLoadStayDetailUseCase(repository: stays),
      reserve: DefaultReserveStayUseCase(repository: LiveReservationsRepository(client: client))
    )
  }
}
