import Foundation
import Testing

// These assertion-shaped helpers keep the existing test expressions readable
// while moving their execution to Swift Testing's `#expect`/`#require` macros.
// They are test-target-only compatibility glue and never ship in a product.

/// Small async expectation bridge for tests that previously used callback
/// expectations from the legacy test runtime. Swift Testing deliberately
/// keeps this bridge outside the production framework;
/// this keeps the test's async contract while reporting timeout failures with
/// `#expect`.
final class _TestExpectation: @unchecked Sendable {
  private struct Waiter {
    let token: UInt64
    let continuation: CheckedContinuation<Void, Never>
  }

  private let lock = NSLock()
  private var isFulfilled = false
  private var waiters: [Waiter] = []
  private var cancelledTokens: Set<UInt64> = []
  private var nextToken: UInt64 = 0

  func fulfill() {
    lock.lock()
    guard !isFulfilled else {
      lock.unlock()
      return
    }
    isFulfilled = true
    let pending = waiters
    waiters.removeAll(keepingCapacity: false)
    lock.unlock()
    pending.forEach { $0.continuation.resume() }
  }

  /// Returns when the expectation is fulfilled or the waiting task is cancelled. A cancelled wait returns without
  /// fulfillment, so `_fulfillment`'s timeout can end its task group instead of waiting forever.
  func wait() async {
    let token = makeWaitToken()
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if register(token: token, continuation: continuation) { continuation.resume() }
      }
    } onCancel: {
      cancelWait(token: token)?.resume()
    }
  }

  // The lock is only taken in these synchronous helpers: NSLock is unavailable from asynchronous contexts.
  private func makeWaitToken() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    nextToken &+= 1
    return nextToken
  }

  /// Parks `continuation` under `token`. Returns true when it must resume at once (already fulfilled, or cancelled
  /// before registration).
  private func register(token: UInt64, continuation: CheckedContinuation<Void, Never>) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if isFulfilled || cancelledTokens.remove(token) != nil { return true }
    waiters.append(Waiter(token: token, continuation: continuation))
    return false
  }

  /// Removes the parked waiter for `token`, returning its continuation for the caller to resume. A cancellation
  /// that arrives before registration leaves a marker that the registration consumes.
  private func cancelWait(token: UInt64) -> CheckedContinuation<Void, Never>? {
    lock.lock()
    defer { lock.unlock() }
    if let index = waiters.firstIndex(where: { $0.token == token }) {
      return waiters.remove(at: index).continuation
    }
    cancelledTokens.insert(token)
    return nil
  }
}

func _makeExpectation(description: String = "") -> _TestExpectation {
  _TestExpectation()
}

func _fulfillment(of expectations: [_TestExpectation], timeout: Double) async {
  let completed = await withTaskGroup(of: Bool.self) { group -> Bool in
    group.addTask {
      for expectation in expectations {
        await expectation.wait()
      }
      return true
    }
    group.addTask {
      // Every suite shares the main actor now, so a wait can sit behind other suites'
      // synchronous work, and the whole suite on a runner with few cores can take well over ten seconds to reach it; a generous
      // floor keeps the wait from being a timing test (a wait that completes returns at once, so the floor costs nothing).
      let nanoseconds = UInt64(max(60, timeout) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      return false
    }
    let result = await group.next() ?? false
    group.cancelAll()
    return result
  }
  #expect(completed)
}

/// Swift Testing intentionally does not provide the legacy implicit benchmark
/// API. Keep these lightweight render smoke benchmarks in the suite while
/// leaving measurement policy to the repository's dedicated benchmark tools.
@inline(__always)
func _measure(_ body: () -> Void) {
  body()
}

@inline(__always)
func _expectTrue(
  _ value: @autoclosure () -> Bool,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(value())
}

@inline(__always)
func _expectFalse(
  _ value: @autoclosure () -> Bool,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(!value())
}

@inline(__always)
func _expectEqual<T: BinaryFloatingPoint>(
  _ lhs: @autoclosure () throws -> T,
  _ rhs: @autoclosure () throws -> T,
  _ message: String = "",
  accuracy: T,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    let left = try lhs()
    let right = try rhs()
    #expect(abs(left - right) <= accuracy)
  } catch {
    #expect(Bool(false))
  }
}

@inline(__always)
func _expectEqual<T: Equatable>(
  _ lhs: @autoclosure () throws -> T,
  _ rhs: @autoclosure () throws -> T,
  _ message: String = "",
  accuracy: T? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    let left = try lhs()
    let right = try rhs()
    #expect(left == right)
  } catch {
    #expect(Bool(false))
  }
}

@inline(__always)
func _expectNotEqual<T: Equatable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() != rhs())
}

@inline(__always)
func _expectNil<T>(
  _ value: @autoclosure () -> T?,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(value() == nil)
}

@inline(__always)
func _expectNotNil<T>(
  _ value: @autoclosure () -> T?,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(value() != nil)
}

@inline(__always)
func _expectGreaterThan<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() > rhs())
}

@inline(__always)
func _expectGreaterThanOrEqual<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() >= rhs())
}

@inline(__always)
func _expectLessThan<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() < rhs())
}

@inline(__always)
func _expectLessThanOrEqual<T: Comparable>(
  _ lhs: @autoclosure () -> T,
  _ rhs: @autoclosure () -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(lhs() <= rhs())
}

@inline(__always)
func _expectThrows<T>(
  _ expression: @autoclosure () throws -> T,
  _ handler: ((any Error) -> Void)? = nil,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    _ = try expression()
    #expect(Bool(false))
  } catch {
    handler?(error)
  }
}

@inline(__always)
func _expectNoThrow<T>(
  _ expression: @autoclosure () throws -> T,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    _ = try expression()
  } catch {
    #expect(Bool(false))
  }
}

@inline(__always)
func _fail(
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) {
  #expect(Bool(false), "\(message)")
}

@inline(__always)
func _require<T>(
  _ expression: @autoclosure () throws -> T?,
  _ message: String = "",
  file: StaticString = #filePath,
  line: UInt = #line
) throws -> T {
  try #require(try expression())
}

/// Runs the observation refresh that a model's `objectWillChange` scheduled in the current turn (SwiftUI updates after a
/// model write, not inside it). Tests that read a rendered tree after writing a model await this first.
@MainActor func _settleObservedRefreshes() async {
  for _ in 0..<3 { await Task.yield() }
}
