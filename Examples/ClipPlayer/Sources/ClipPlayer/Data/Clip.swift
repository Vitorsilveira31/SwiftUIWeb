import Foundation

/// One video the screen can play. Two are progressive MP4 files and two are HLS streams, so the same player
/// handles both delivery styles.
struct Clip: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let url: URL

    /// Fails for a malformed literal instead of trapping on a force unwrap.
    init?(id: String, title: String, detail: String, urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.id = id
        self.title = title
        self.detail = detail
        self.url = url
    }
}
