/// Where the stays come from: the list, and one stay's page.
protocol StaysRepository: Sendable {
  func stays() async throws -> [Stay]
  func detail(stayID: Int) async throws -> StayDetail
}
