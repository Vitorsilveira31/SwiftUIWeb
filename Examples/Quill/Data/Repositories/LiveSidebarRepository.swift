import CloneKit

/// The people to follow (every user but the reader, three of them) and the trends (the albums of the first two users, five of them).
struct LiveSidebarRepository: SidebarRepository {
  let client: PlaceholderClient
  let currentUserID: Int
  static let suggestionLimit = 3
  static let trendLimit = 5

  func suggestions() async throws -> [QuillUser] {
    try await client.users()
      .filter { $0.id != currentUserID }
      .prefix(LiveSidebarRepository.suggestionLimit)
      .map(QuillMapping.user)
  }

  func trends() async throws -> [QuillTrend] {
    let first = try await client.albums(userId: 1)
    let second = try await client.albums(userId: 2)
    return (first + second).prefix(LiveSidebarRepository.trendLimit).map(QuillMapping.trend)
  }
}
