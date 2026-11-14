import CloneKit

/// The people from the API's users, in the order the service gives them.
struct LivePeopleRepository: PeopleRepository {
  let client: PlaceholderClient

  func people() async throws -> [NeighborlyUser] {
    try await client.users().map { NeighborlyUser(placeholder: $0) }
  }
}
