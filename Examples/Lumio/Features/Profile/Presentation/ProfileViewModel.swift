import SwiftUIWeb

/// A profile's state.
@MainActor @Observable
final class ProfileViewModel {
  private(set) var profile: LumioProfile?
  private(set) var state: LoadState = .loading
  private let userID: Int
  private let loadProfile: any LoadProfileUseCase

  init(userID: Int, load: any LoadProfileUseCase) {
    self.userID = userID
    loadProfile = load
  }

  func load() async {
    state = .loading
    do {
      profile = try await loadProfile.execute(userID: userID)
      state = .loaded
    } catch {
      state = .failed(FailureText.unreachable)
    }
  }
}
