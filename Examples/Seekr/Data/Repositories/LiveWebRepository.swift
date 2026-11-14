import CloneKit

/// The web results from the API's posts. Each post is paired with the user who wrote it: the site is that user's website, and the
/// questions are the comments on the top result (their names, as the questions people ask).
struct LiveWebRepository: WebRepository {
  let client: PlaceholderClient
  static let pageSize = 10
  static let questionCount = 3
  static let snippetLength = 180

  func results(query: String, page: Int) async throws -> SeekrResultPage {
    let posts = try await client.searchPosts(query: query, page: page, limit: LiveWebRepository.pageSize)
    return try await pageOf(posts, query: query)
  }

  func news(query: String, page: Int) async throws -> SeekrResultPage {
    let posts = try await client.newestPosts(query: query, page: page, limit: LiveWebRepository.pageSize)
    return try await pageOf(posts, query: query)
  }

  func questions(query: String) async throws -> [String] {
    guard let top = try await client.searchPosts(query: query, page: 1, limit: 1).first else { return [] }
    return try await client.comments(postId: top.id).prefix(LiveWebRepository.questionCount).map { question($0.name) }
  }

  /// A comment's name without the spaces the service may leave at its end, as a question reads.
  private func question(_ name: String) -> String {
    String(name.reversed().drop { $0 == " " }.reversed())
  }

  /// The results of one page, with the total the query has (counted over every matching post).
  private func pageOf(_ posts: [PlaceholderPost], query: String) async throws -> SeekrResultPage {
    async let matches = client.matchingPosts(query: query)
    async let sites = websites()
    let (all, names) = try await (matches, sites)
    return SeekrResultPage(results: posts.map { result($0, sites: names) }, total: all.count)
  }

  private func result(_ post: PlaceholderPost, sites: [Int: String]) -> SeekrResult {
    let site = sites[post.userId] ?? ""
    return SeekrResult(
      id: post.id,
      title: post.title,
      site: site,
      // The site comes from the service: anything but a plain host name would reshape the link, so no link is shown.
      link: LiveWebRepository.isHostName(site) ? "https://\(site)/posts/\(post.id)" : "",
      snippet: String(post.body.prefix(LiveWebRepository.snippetLength))
    )
  }

  /// Letters, digits, "-" and "." only, as a host name has them.
  private static func isHostName(_ site: String) -> Bool {
    !site.isEmpty && site.utf8.allSatisfy { byte in
      (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x2E
    }
  }

  private func websites() async throws -> [Int: String] {
    var sites: [Int: String] = [:]
    for user in try await client.users() { sites[user.id] = user.website }
    return sites
  }
}
