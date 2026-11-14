import CloneKit

/// How the API's resources become Quill's: a user's handle and picture, a post's counts, a reply's author, a trend.
enum QuillMapping {
  /// The mock service keeps five replies under each post; the thread shows them, so the count says the same.
  static let repliesPerPost = 5

  static func user(_ user: PlaceholderUser) -> QuillUser {
    QuillUser(id: user.id, name: user.name, handle: "@\(user.username)", avatarURL: PlaceholderImage.avatar(user.id, size: 128))
  }

  /// The service has no counts for a post, so they come from its id: the same for everyone, and the same on every load.
  static func post(_ post: PlaceholderPost, author: QuillUser) -> QuillPost {
    // Wrapping multiply on the magnitude: server ids can be large, and Int is 32 bits in the browser build.
    QuillPost(
      id: post.id,
      author: author,
      text: String(post.body.map { $0 == "\n" ? " " : $0 }),
      likes: Int((post.id.magnitude &* 37) % 240) + 3,
      reposts: Int((post.id.magnitude &* 13) % 60),
      replies: repliesPerPost
    )
  }

  static func reply(_ comment: PlaceholderComment) -> QuillReply {
    QuillReply(
      id: comment.id,
      name: comment.email.split(separator: "@").first.map(String.init) ?? comment.email,
      text: comment.body,
      avatarURL: PlaceholderImage.avatar(comment.id % 10 + 1, size: 128)
    )
  }

  static func trend(_ album: PlaceholderAlbum) -> QuillTrend {
    QuillTrend(id: album.id, topic: album.title, posts: Int((album.id.magnitude &* 53) % 900) + 40)
  }
}
