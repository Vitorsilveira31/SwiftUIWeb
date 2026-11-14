/// Where the web results come from: the posts that match a query (all, or the newest of them as News), and the questions people ask about the top one.
protocol WebRepository: Sendable {
  func results(query: String, page: Int) async throws -> SeekrResultPage
  func news(query: String, page: Int) async throws -> SeekrResultPage
  func questions(query: String) async throws -> [String]
}
