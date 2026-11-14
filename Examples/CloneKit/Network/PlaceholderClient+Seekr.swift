import SwiftUIWeb

/// The calls of a web search: the posts that match a query, a page at a time, and the same posts newest first (Seekr's News).
/// The query is the service's `q` (a full-text match over each post), so the mock and jsonplaceholder answer alike.
extension PlaceholderClient {
  /// A page of the posts that match `query`, in the service's order.
  public func searchPosts(query: String, page: Int, limit: Int) async throws -> [PlaceholderPost] {
    try JSONDecoder().decode(
      [PlaceholderPost].self,
      from: await transport.send("GET", "\(PlaceholderImage.base)/posts?_page=\(page)&_limit=\(limit)&q=\(PlaceholderQuery.encode(query))", body: nil)
    )
  }

  /// Every post that matches `query`. A page carries no total, so the number of results is counted from this list.
  public func matchingPosts(query: String) async throws -> [PlaceholderPost] {
    try JSONDecoder().decode([PlaceholderPost].self, from: await transport.send("GET", "\(PlaceholderImage.base)/posts?q=\(PlaceholderQuery.encode(query))", body: nil))
  }

  /// A page of the posts that match `query`, the newest (the highest id) first.
  public func newestPosts(query: String, page: Int, limit: Int) async throws -> [PlaceholderPost] {
    try JSONDecoder().decode(
      [PlaceholderPost].self,
      from: await transport.send("GET", "\(PlaceholderImage.base)/posts?_sort=id&_order=desc&_page=\(page)&_limit=\(limit)&q=\(PlaceholderQuery.encode(query))", body: nil)
    )
  }
}
