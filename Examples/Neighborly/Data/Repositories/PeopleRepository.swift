/// Where the people of Neighborly come from: the contacts in the right column and the people in the Photos picker.
protocol PeopleRepository: Sendable {
  func people() async throws -> [NeighborlyUser]
}
