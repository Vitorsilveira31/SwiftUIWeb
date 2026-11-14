/// What a screen says when a request failed. Embedded Swift cannot print an arbitrary error, so the reason is the same for all.
enum FailureText {
  static let unreachable = "The service could not be reached. Check that the API is running, then try again."
}
