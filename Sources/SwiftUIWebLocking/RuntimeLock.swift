#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Mutual exclusion for the few process-wide registries that native hosts may
/// touch from several threads (for example media players created by
/// concurrently running tests). The browser runtime is single-threaded, so
/// the Embedded/WASI form is a zero-cost pass-through.
@_spi(Renderer) public final class _RuntimeLock: @unchecked Sendable {
  #if hasFeature(Embedded) || os(WASI) || !(canImport(Darwin) || canImport(Glibc) || canImport(Musl))
  public init(recursive: Bool = true) {}
  @inline(__always)
  public func withLock<Result>(_ body: () throws -> Result) rethrows -> Result { try body() }
  public func lock() {}
  public func unlock() {}
  public func tryLock() -> Bool { true }
  #else
  private let mutex: UnsafeMutablePointer<pthread_mutex_t>

  /// Recursive by default: registries may call back into themselves (for example a deinit that unregisters while a
  /// lookup prunes a released entry). `NSLock` asks for a plain mutex.
  public init(recursive: Bool = true) {
    mutex = .allocate(capacity: 1)
    var attributes = pthread_mutexattr_t()
    pthread_mutexattr_init(&attributes)
    pthread_mutexattr_settype(&attributes, Int32(recursive ? PTHREAD_MUTEX_RECURSIVE : PTHREAD_MUTEX_NORMAL))
    pthread_mutex_init(mutex, &attributes)
    pthread_mutexattr_destroy(&attributes)
  }

  deinit {
    pthread_mutex_destroy(mutex)
    mutex.deallocate()
  }

  public func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
    pthread_mutex_lock(mutex)
    defer { pthread_mutex_unlock(mutex) }
    return try body()
  }

  public func lock() { pthread_mutex_lock(mutex) }
  public func unlock() { pthread_mutex_unlock(mutex) }
  public func tryLock() -> Bool { pthread_mutex_trylock(mutex) == 0 }
  #endif
}

/// A value that several threads may reach, guarded by a lock. It replaces
/// `nonisolated(unsafe)` globals: the state is only reachable through `withLock`.
@_spi(Renderer) public final class _Locked<Value>: @unchecked Sendable {
  private let lock = _RuntimeLock()
  private var value: Value
  public init(_ value: Value) { self.value = value }
  @inline(__always)
  public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try lock.withLock { try body(&value) }
  }
}
