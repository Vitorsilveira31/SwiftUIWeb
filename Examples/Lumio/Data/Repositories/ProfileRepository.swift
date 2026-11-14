/// Where a person's profile comes from.
protocol ProfileRepository: Sendable {
  func profile(userID: Int) async throws -> LumioProfile
}
