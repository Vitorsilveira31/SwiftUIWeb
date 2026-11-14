@testable import SwiftUIWebSecurity

/// A store whose `loadAll()` waits until the test opens it, so a test can act while an `unlock()`
/// is still loading; `failure` makes that load fail once opened.
actor GatedSecretStore: WebSecretStore {
  private let items: [(id: String, value: [UInt8])]
  private let failure: WebSecurityError?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var loads = 0

  init(items: [(id: String, value: [UInt8])] = [], failure: WebSecurityError? = nil) {
    self.items = items
    self.failure = failure
  }

  var waiting: Int { waiters.count }

  func loadAll() async throws(WebSecurityError) -> [(id: String, value: [UInt8])] {
    loads += 1
    await withCheckedContinuation { waiters.append($0) }
    if let failure { throw failure }
    return items
  }

  /// Lets every load waiting so far finish.
  func open() {
    let pending = waiters
    waiters.removeAll()
    for waiter in pending { waiter.resume() }
  }

  func save(_ value: [UInt8], id: String) async throws(WebSecurityError) {}
  func remove(id: String) async throws(WebSecurityError) {}
  func removeAll() async throws(WebSecurityError) {}

  /// Waits until `count` loads are suspended in `loadAll()`; `false` if they never are, so a test
  /// whose load does not start fails instead of hanging.
  func untilWaiting(_ count: Int) async -> Bool {
    for _ in 0..<100_000 where waiters.count < count { await Task.yield() }
    return waiters.count >= count
  }
}
