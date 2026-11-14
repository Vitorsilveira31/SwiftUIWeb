#if !os(WASI)
import Foundation
import Testing
@testable @_spi(Renderer) import SwiftUIWebLocking

/// Hands one value from a host thread to the test. Both sides meet under the same mutex, so a value delivered
/// before the wait is never missed.
private final class ThreadMailbox<Value>: @unchecked Sendable {
  private let condition = _RuntimeCondition()
  private var value: Value?

  func deliver(_ newValue: Value) {
    condition.lock()
    value = newValue
    condition.broadcast()
    condition.unlock()
  }

  /// Waits until a value arrives or the time runs out.
  func receive(within seconds: Double) -> Value? {
    condition.lock()
    defer { condition.unlock() }
    var waited = 0.0
    while value == nil && waited < seconds {
      _ = condition.wait(seconds: 0.05)
      waited += 0.05
    }
    return value
  }
}

/// Shared state for a two-thread handshake. Every field is read and written under `condition`.
private final class ConditionHandshake: @unchecked Sendable {
  let condition = _RuntimeCondition()
  var ready = false
  var woke = false
}

/// Holds a `_RuntimeLock` on a host thread until the test releases it.
private final class LockHolder: @unchecked Sendable {
  let lock = _RuntimeLock()
  let condition = _RuntimeCondition()
  var held = false
  var released = false
  var finished = false
}

private final class ThreadLocalBox {}

/// Polls `flag` under `condition`'s mutex for a bounded time. `flag` reads state guarded by that mutex.
private func awaitFlag(_ condition: _RuntimeCondition, _ flag: () -> Bool) {
  condition.lock()
  defer { condition.unlock() }
  var waited = 0.0
  while !flag() && waited < 5 {
    _ = condition.wait(seconds: 0.05)
    waited += 0.05
  }
}

@Suite(.serialized) struct HostThreadDetachCoverageTests {
  @Test func hostThreadsAreAvailableOnNativePlatforms() {
    #expect(_swiftUIWebHostHasThreads)
  }

  @Test func detachedThreadRunsTheBodyOffTheMainThread() {
    let mailbox = ThreadMailbox<Bool>()
    let started = _swiftUIWebDetachHostThread {
      mailbox.deliver(_swiftUIWebHostIsMainThread())
    }
    #expect(started)
    #expect(mailbox.receive(within: 5) == false)
  }

  @Test func sleepReturnsAtOnceForNonPositiveDurations() {
    let elapsed = ContinuousClock().measure {
      _swiftUIWebHostSleep(seconds: 0)
      _swiftUIWebHostSleep(seconds: -1)
    }
    #expect(elapsed < .seconds(1))
  }

  @Test func sleepBlocksForAtLeastTheRequestedDuration() {
    let elapsed = ContinuousClock().measure {
      _swiftUIWebHostSleep(seconds: 0.05)
    }
    #expect(elapsed >= .milliseconds(40))
  }
}

@Suite(.serialized) struct HostRuntimeConditionCoverageTests {
  @Test func timedWaitWithoutSignalReportsTimeout() {
    let condition = _RuntimeCondition()
    condition.lock()
    let signalled = condition.wait(seconds: 0.01)
    condition.unlock()
    #expect(signalled == false)
  }

  @Test func signalWakesAWaiterWhosePredicateIsSet() {
    let handshake = ConditionHandshake()
    let started = _swiftUIWebDetachHostThread {
      handshake.condition.lock()
      while !handshake.ready { handshake.condition.wait() }
      handshake.woke = true
      handshake.condition.broadcast()
      handshake.condition.unlock()
    }
    #expect(started)

    handshake.condition.lock()
    handshake.ready = true
    handshake.condition.signal()
    handshake.condition.unlock()

    awaitFlag(handshake.condition) { handshake.woke }
    handshake.condition.lock()
    let woke = handshake.woke
    handshake.condition.unlock()
    #expect(woke)
  }

  @Test func broadcastWakesEveryWaiter() {
    let handshake = ConditionHandshake()
    let mailbox = ThreadMailbox<Bool>()
    let started = _swiftUIWebDetachHostThread {
      handshake.condition.lock()
      while !handshake.ready { handshake.condition.wait() }
      handshake.condition.unlock()
      mailbox.deliver(true)
    }
    #expect(started)

    handshake.condition.lock()
    handshake.ready = true
    handshake.condition.broadcast()
    handshake.condition.unlock()

    #expect(mailbox.receive(within: 5) == true)
  }

  @Test func unlockedConditionCanBeLockedAndUnlockedRepeatedly() {
    let condition = _RuntimeCondition()
    for _ in 0..<3 {
      condition.lock()
      condition.unlock()
    }
  }
}

@Suite(.serialized) struct HostThreadLocalCoverageTests {
  @Test func threadLocalReturnsTheSameValueOnRepeatedReads() {
    let local = _ThreadLocal { ThreadLocalBox() }
    let first = local.current
    #expect(first === local.current)
  }

  @Test func threadLocalCreatesADistinctValueOnAnotherThread() {
    let local = _ThreadLocal { ThreadLocalBox() }
    let mainValueID = ObjectIdentifier(local.current)
    let mailbox = ThreadMailbox<Bool>()
    let started = _swiftUIWebDetachHostThread {
      mailbox.deliver(ObjectIdentifier(local.current) != mainValueID)
    }
    #expect(started)
    #expect(mailbox.receive(within: 5) == true)
  }
}

@Suite(.serialized) struct RuntimeLockCoverageTests {
  @Test func tryLockSucceedsOnAFreeLockUntilUnlocked() {
    let lock = _RuntimeLock()
    #expect(lock.tryLock())
    lock.unlock()
    #expect(lock.tryLock())
    lock.unlock()
  }

  @Test func tryLockFailsWhileAnotherThreadHoldsTheLock() {
    let holder = LockHolder()
    let started = _swiftUIWebDetachHostThread {
      holder.lock.lock()
      holder.condition.lock()
      holder.held = true
      holder.condition.broadcast()
      while !holder.released { holder.condition.wait() }
      holder.condition.unlock()
      holder.lock.unlock()
      holder.condition.lock()
      holder.finished = true
      holder.condition.broadcast()
      holder.condition.unlock()
    }
    #expect(started)

    awaitFlag(holder.condition) { holder.held }
    #expect(holder.lock.tryLock() == false)

    holder.condition.lock()
    holder.released = true
    holder.condition.broadcast()
    holder.condition.unlock()

    awaitFlag(holder.condition) { holder.finished }
    #expect(holder.lock.tryLock())
    holder.lock.unlock()
  }

  @Test func withLockReleasesTheLockWhenTheBodyThrows() {
    struct BodyFailure: Error {}
    let lock = _RuntimeLock()
    #expect(throws: BodyFailure.self) {
      try lock.withLock { () throws -> Int in throw BodyFailure() }
    }
    #expect(lock.tryLock())
    lock.unlock()
  }

  @Test func withLockReturnsTheBodyResult() {
    let lock = _RuntimeLock()
    #expect(lock.withLock { 42 } == 42)
  }
}
#endif
