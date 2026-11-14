#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The operating system's wall clock, in seconds since 1970, on hosts that have one (macOS, Linux, Android).
/// The browser installs its own clock through `SwiftUIWebDateRuntime`; Embedded and WASI builds have none here,
/// which keeps their renderer fixtures deterministic.
package func _swiftUIWebHostWallClockSeconds() -> Double? {
  #if hasFeature(Embedded) || os(WASI) || !(canImport(Darwin) || canImport(Glibc) || canImport(Musl))
  return nil
  #else
  var now = timespec()
  clock_gettime(CLOCK_REALTIME, &now)
  return Double(now.tv_sec) + Double(now.tv_nsec) / 1_000_000_000
  #endif
}
