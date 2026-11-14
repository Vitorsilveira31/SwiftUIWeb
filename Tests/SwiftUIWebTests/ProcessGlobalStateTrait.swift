import Testing

/// Serializes tests that configure genuinely process-wide runtime state.
///
/// Render-pass state (environment, state scope, animation transaction and
/// memory counters) is thread-confined, so ordinary view tests run in
/// parallel. A few runtimes are process-wide by design, exactly like their
/// Apple counterparts (`UserDefaults.standard`, the system color scheme,
/// installed network transports, share/scroll/accessibility hosts). Tests
/// that install or replace one of those hosts hold this gate for their whole
/// body, so they never observe each other's configuration while every other
/// test keeps running concurrently.
///
/// A suite that installs hosts removes them in `tearDown`, which runs inside the gate after each test. A `deinit` does
/// not: the test's instance is released whenever its last reference goes, and a network suite's `deinit` removed the
/// transports the next test holding the gate had just installed (its requests then went to the native adapter).
struct ProcessGlobalStateTrait: TestTrait, SuiteTrait, TestScoping {
  var tearDown: (@MainActor @Sendable () -> Void)?

  var isRecursive: Bool { true }

  func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
    testCase == nil ? nil : self
  }

  func provideScope(
    for test: Test,
    testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    await ProcessGlobalStateGate.shared.acquire()
    do {
      try await function()
    } catch {
      if let tearDown { await tearDown() }
      await ProcessGlobalStateGate.shared.release()
      throw error
    }
    if let tearDown { await tearDown() }
    await ProcessGlobalStateGate.shared.release()
  }
}

extension Trait where Self == ProcessGlobalStateTrait {
  /// The test (or every test of the suite) configures process-wide runtime
  /// hosts and must not overlap another such test.
  static var processGlobalState: Self { Self() }

  /// The same, with `tearDown` run inside the gate after each test (see `ProcessGlobalStateTrait`).
  static func processGlobalState(tearDown: @escaping @MainActor @Sendable () -> Void) -> Self { Self(tearDown: tearDown) }
}

private actor ProcessGlobalStateGate {
  static let shared = ProcessGlobalStateGate()
  private var held = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    guard held else {
      held = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty {
      held = false
    } else {
      waiters.removeFirst().resume()
    }
  }
}
