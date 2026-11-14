/// Where the right column comes from: the people to follow and the trends.
protocol SidebarRepository: Sendable {
  func suggestions() async throws -> [QuillUser]
  func trends() async throws -> [QuillTrend]
}
