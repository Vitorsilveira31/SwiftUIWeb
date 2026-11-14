#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// The operating system's threads, for WebFoundation's `Thread` and `NSCondition`. The browser has one page thread:
// there these answer "main thread", start nothing, and never block.

#if hasFeature(Embedded) || os(WASI) || !(canImport(Darwin) || canImport(Glibc) || canImport(Musl))
package let _swiftUIWebHostHasThreads = false
package func _swiftUIWebDetachHostThread(_ body: @escaping @Sendable () -> Void) -> Bool { false }
package func _swiftUIWebHostIsMainThread() -> Bool { true }
package func _swiftUIWebHostSleep(seconds: Double) {}

package final class _RuntimeCondition: @unchecked Sendable {
  package init() {}
  package func lock() {}
  package func unlock() {}
  package func wait() {}
  package func wait(seconds: Double) -> Bool { false }
  package func signal() {}
  package func broadcast() {}
}

/// One value per thread; single-threaded hosts have one value.
package final class _ThreadLocal<Value: AnyObject>: @unchecked Sendable {
  private let make: () -> Value
  private var value: Value?
  package init(_ make: @escaping () -> Value) { self.make = make }
  package var current: Value {
    if let value { return value }
    let created = make()
    value = created
    return created
  }
}
#else
package let _swiftUIWebHostHasThreads = true

private final class _ThreadStart {
  let body: @Sendable () -> Void
  init(_ body: @escaping @Sendable () -> Void) { self.body = body }
}

/// Starts a detached OS thread running `body`.
package func _swiftUIWebDetachHostThread(_ body: @escaping @Sendable () -> Void) -> Bool {
  let start = Unmanaged.passRetained(_ThreadStart(body)).toOpaque()
  #if canImport(Darwin)
  var thread: pthread_t?
  #else
  var thread = pthread_t()
  #endif
  let status = pthread_create(&thread, nil, { argument in
    #if canImport(Darwin)
    let start = Unmanaged<_ThreadStart>.fromOpaque(argument).takeRetainedValue()
    #else
    let start = Unmanaged<_ThreadStart>.fromOpaque(argument!).takeRetainedValue()
    #endif
    start.body()
    return nil
  }, start)
  guard status == 0 else {
    Unmanaged<_ThreadStart>.fromOpaque(start).release()
    return false
  }
  #if canImport(Darwin)
  if let thread { pthread_detach(thread) }
  #else
  pthread_detach(thread)
  #endif
  return true
}

package func _swiftUIWebHostIsMainThread() -> Bool {
  #if canImport(Darwin)
  return pthread_main_np() != 0
  #else
  // Swift's Glibc module does not expose `gettid`; `/proc/thread-self` links to `<pid>/task/<tid>`, and the main
  // thread is the one whose thread id is the process id.
  var buffer = [CChar](repeating: 0, count: 64)
  let count = readlink("/proc/thread-self", &buffer, buffer.count - 1)
  guard count > 0 else { return true }
  let text = String(decoding: buffer[0..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self)
  let parts = text.split(separator: "/")
  guard parts.count == 3, parts[1] == "task" else { return true }
  return parts[0] == parts[2]
  #endif
}

package func _swiftUIWebHostSleep(seconds: Double) {
  // NaN fails the guard; an infinite sleep is capped (about 31 years), since Int(infinity) traps.
  guard seconds > 0 else { return }
  let bounded = Swift.min(seconds, 1.0e9)
  var request = timespec(tv_sec: Int(bounded), tv_nsec: Int((bounded - bounded.rounded(.down)) * 1_000_000_000))
  var remaining = timespec()
  while nanosleep(&request, &remaining) != 0 { request = remaining }
}

/// A mutex with a condition variable.
package final class _RuntimeCondition: @unchecked Sendable {
  private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
  private let condition = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)

  package init() {
    pthread_mutex_init(mutex, nil)
    pthread_cond_init(condition, nil)
  }

  deinit {
    pthread_cond_destroy(condition)
    pthread_mutex_destroy(mutex)
    condition.deallocate()
    mutex.deallocate()
  }

  package func lock() { pthread_mutex_lock(mutex) }
  package func unlock() { pthread_mutex_unlock(mutex) }
  package func wait() { pthread_cond_wait(condition, mutex) }
  package func signal() { pthread_cond_signal(condition) }
  package func broadcast() { pthread_cond_broadcast(condition) }

  /// Waits at most `seconds`; `false` when the time ran out first.
  package func wait(seconds: Double) -> Bool {
    var now = timespec()
    clock_gettime(CLOCK_REALTIME, &now)
    let target = Double(now.tv_sec) + Double(now.tv_nsec) / 1_000_000_000 + max(0, seconds)
    var deadline = timespec(tv_sec: Int(target), tv_nsec: Int((target - target.rounded(.down)) * 1_000_000_000))
    return pthread_cond_timedwait(condition, mutex, &deadline) == 0
  }
}

/// One value per thread, created on the thread's first read and released when the thread ends.
package final class _ThreadLocal<Value: AnyObject>: @unchecked Sendable {
  private let make: () -> Value
  private let key: pthread_key_t

  package init(_ make: @escaping () -> Value) {
    self.make = make
    var key = pthread_key_t()
    let status = pthread_key_create(&key) { pointer in
      #if canImport(Darwin)
      Unmanaged<AnyObject>.fromOpaque(pointer).release()
      #else
      guard let pointer else { return }
      Unmanaged<AnyObject>.fromOpaque(pointer).release()
      #endif
    }
    precondition(status == 0, "Unable to allocate thread-local storage")
    self.key = key
  }

  package var current: Value {
    if let pointer = pthread_getspecific(key) {
      return unsafeDowncast(Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue(), to: Value.self)
    }
    let value = make()
    pthread_setspecific(key, Unmanaged<AnyObject>.passRetained(value).toOpaque())
    return value
  }
}
#endif
