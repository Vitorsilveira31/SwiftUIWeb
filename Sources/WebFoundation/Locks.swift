// Foundation's locks over the runtime's mutex: a pthread mutex on hosts with threads, nothing in the browser, whose
// page has one thread.
@_spi(Renderer) import SwiftUIWebLocking
@_spi(Renderer) import SwiftUIWebTransferable

public protocol NSLocking {
  func lock()
  func unlock()
}

extension NSLocking {
  /// Runs `body` with the lock held.
  @_disfavoredOverload public func withLock<R>(_ body: () throws -> R) rethrows -> R {
    lock()
    defer { unlock() }
    return try body()
  }
}

/// How the lock classes meet `NSLocking`. Foundation declares `lock()` and `unlock()` only on the protocol, so the classes
/// supply their primitive here instead of members of their own.
public protocol _NSLockingPrimitive: NSLocking {
  func _lockPrimitive()
  func _unlockPrimitive()
}

extension _NSLockingPrimitive {
  public func lock() { _lockPrimitive() }
  public func unlock() { _unlockPrimitive() }
}

open class NSLock: NSObject, _NSLockingPrimitive, @unchecked Sendable {
  private let mutex = _RuntimeLock(recursive: false)
  open var name: String?

  public override init() { super.init() }

  public func _lockPrimitive() { mutex.lock() }
  public func _unlockPrimitive() { mutex.unlock() }
  open func `try`() -> Bool { mutex.tryLock() }

  /// Waits until `limit` for the lock; `false` when it stays held.
  open func lock(before limit: Date) -> Bool {
    while true {
      if mutex.tryLock() { return true }
      if Date() >= limit { return false }
    }
  }
}

/// A lock with a condition: `wait()` releases it until another thread signals.
open class NSCondition: NSObject, _NSLockingPrimitive, @unchecked Sendable {
  private let condition = _RuntimeCondition()
  open var name: String?

  public override init() { super.init() }

  public func _lockPrimitive() { condition.lock() }
  public func _unlockPrimitive() { condition.unlock() }
  open func wait() { condition.wait() }
  /// Waits until `limit`; `false` when it passed without a signal.
  open func wait(until limit: Date) -> Bool { condition.wait(seconds: limit.timeIntervalSince1970 - Date().timeIntervalSince1970) }
  open func signal() { condition.signal() }
  open func broadcast() { condition.broadcast() }
}

/// Foundation's `Thread`, for the parts applications use: where code runs, sleeping, and starting a detached thread.
/// The browser has one page thread, so there `detachNewThread` runs its block on the main actor.
open class Thread: NSObject, @unchecked Sendable {
  public static var isMainThread: Bool { _swiftUIWebHostIsMainThread() }
  open var isMainThread: Bool { _swiftUIWebHostIsMainThread() }
  public static var current: Thread { Thread() }
  public static var main: Thread { Thread() }

  public static func sleep(forTimeInterval interval: TimeInterval) { _swiftUIWebHostSleep(seconds: interval) }
  public static func sleep(until date: Date) { _swiftUIWebHostSleep(seconds: date.timeIntervalSince1970 - Date().timeIntervalSince1970) }

  public static func detachNewThread(_ block: @escaping @Sendable () -> Void) {
    if !_swiftUIWebDetachHostThread(block) { Task { @MainActor in block() } }
  }

  public override init() { super.init() }
}

open class NSRecursiveLock: NSObject, _NSLockingPrimitive, @unchecked Sendable {
  private let mutex = _RuntimeLock(recursive: true)
  open var name: String?

  public override init() { super.init() }

  public func _lockPrimitive() { mutex.lock() }
  public func _unlockPrimitive() { mutex.unlock() }
  open func `try`() -> Bool { mutex.tryLock() }

  open func lock(before limit: Date) -> Bool {
    while true {
      if mutex.tryLock() { return true }
      if Date() >= limit { return false }
    }
  }
}
