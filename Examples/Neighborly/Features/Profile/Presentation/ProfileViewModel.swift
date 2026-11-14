import SwiftUIWeb

/// The profile the Profile tab shows: whose it is, and the profile once it has come.
@MainActor @Observable
final class ProfileViewModel {
  private(set) var profile: NeighborlyProfile?
  private(set) var state: LoadState = .loading
  private(set) var userID: Int
  /// Counts the loads started; a result that finishes after a newer load started is dropped.
  private var loadSerial = 0
  private let loadProfile: any LoadProfileUseCase

  init(userID: Int, load: any LoadProfileUseCase) {
    self.userID = userID
    loadProfile = load
  }

  /// Shows another person's profile: the old one goes away while the new one loads.
  func show(userID id: Int) async {
    userID = id
    profile = nil
    await load()
  }

  /// The profile of the person shown; also what Try again runs.
  func load() async {
    loadSerial += 1
    let current = loadSerial
    state = .loading
    do {
      let found = try await loadProfile.execute(userID: userID)
      guard current == loadSerial else { return }
      profile = found
      state = .loaded
    } catch {
      guard current == loadSerial else { return }
      state = .failed(FailureText.unreachable)
    }
  }
}
