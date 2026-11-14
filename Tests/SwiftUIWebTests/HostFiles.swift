#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The test host's own disk, for the few tests that read or write files of the repository (fixtures, reports a tool
/// reads later). Application code, and so `FileManager` and `Data(contentsOf:)`, sees SwiftUIWeb's virtual file
/// system instead, on every host.
enum HostFiles {
  /// The directory of the test source that calls it, from `#filePath`.
  static func directory(of filePath: String = #filePath) -> String {
    guard let slash = filePath.lastIndex(of: "/") else { return "." }
    return String(filePath[..<slash])
  }

  /// A variable of the test process's own environment. `ProcessInfo` reads SwiftUIWeb's host-neutral environment,
  /// which is empty on a native test host, so a test switch such as `SWIFTUIWEB_UPDATE_BINARY_FIXTURES=1` reads it here.
  static func environment(_ key: String) -> String? {
    getenv(key).map { String(cString: $0) }
  }

  /// `path`'s parent directory.
  static func parent(_ path: String) -> String {
    guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
    return String(path[..<slash])
  }

  static func read(_ path: String) -> [UInt8]? {
    guard let file = fopen(path, "rb") else { return nil }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65_536)
    while true {
      let count = fread(&chunk, 1, chunk.count, file)
      if count > 0 { bytes.append(contentsOf: chunk[0..<count]) }
      if count < chunk.count { break }
    }
    return ferror(file) == 0 ? bytes : nil
  }

  @discardableResult
  static func write(_ bytes: [UInt8], to path: String) -> Bool {
    makeDirectory(parent(path))
    guard let file = fopen(path, "wb") else { return false }
    defer { fclose(file) }
    return bytes.withUnsafeBufferPointer { fwrite($0.baseAddress, 1, $0.count, file) } == bytes.count
  }

  /// Creates `path` and its missing parents.
  static func makeDirectory(_ path: String) {
    var current = path.hasPrefix("/") ? "" : "."
    for component in path.split(separator: "/") {
      current += "/" + component
      _ = mkdir(current, 0o755)
    }
  }
}
