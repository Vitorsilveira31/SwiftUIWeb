/// The words of a profile.
enum ProfileStrings {
  static let loading = "Loading the profile…"
  static let failedTitle = "The profile could not load"
  static let retry = "Try again"
  static let posts = "posts"
  static let albums = "albums"
  static let friends = "friends"
  static let friendsTitle = "Friends"
  static let noFriends = "No friends to show yet"

  static func from(_ city: String) -> String { "From \(city)" }
}
