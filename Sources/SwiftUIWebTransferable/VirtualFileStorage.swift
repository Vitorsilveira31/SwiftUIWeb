@_spi(Renderer) import SwiftUIWebLocking

// The one file system SwiftUIWeb applications see, on every host: an in-memory tree that lives as long as the
// process (the page, in the browser). WebFoundation's `FileManager`, `Data.write(to:)` and `Data(contentsOf:)` and
// `Transferable.export(to:)` all resolve against it, so a file written on one path reads back the same everywhere.

package struct FileSystemError: Error, Sendable {
  package enum Reason: Sendable { case noSuchFile, fileExists, notADirectory, unsupported }
  package let reason: Reason
  package let path: String
  package init(reason: Reason, path: String) { self.reason = reason; self.path = path }
}

/// Paths are absolute and normalized (`/tmp/a`, never `/tmp/./a/` or `tmp/a`). Every access holds the runtime lock:
/// native test runners touch the tree from several threads, the browser from one.
package final class _VirtualFileSystem: @unchecked Sendable {
  package static let shared = _VirtualFileSystem()
  private let lock = _RuntimeLock()
  private var files: [String: Data] = .init()
  private var directories: Set<String> = ["/", "/tmp", "/Documents", "/Library", "/Library/Caches", "/Library/Application Support"]

  package static func normalized(_ path: String) -> String {
    var parts: [Substring] = []
    for part in path.split(separator: "/", omittingEmptySubsequences: true) {
      if part == "." { continue }
      if part == ".." { _ = parts.popLast(); continue }
      parts.append(part)
    }
    return "/" + parts.joined(separator: "/")
  }

  package static func parent(_ path: String) -> String {
    guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
    return String(path[..<slash])
  }

  /// The tree path a `file://` URL (or a bare path) names: the scheme and host dropped, `%XX` escapes decoded.
  package static func path(of url: URL) -> String {
    var bytes = Array(url.absoluteString.utf8)
    let scheme = Array("file://".utf8)
    if bytes.starts(with: scheme) {
      bytes.removeFirst(scheme.count)
      if let slash = bytes.firstIndex(of: UInt8(ascii: "/")) { bytes.removeFirst(slash) } else { bytes = [] }
    }
    var decoded: [UInt8] = []
    decoded.reserveCapacity(bytes.count)
    var index = 0
    while index < bytes.count {
      if bytes[index] == UInt8(ascii: "%"), index + 2 < bytes.count,
         let high = _hexDigit(bytes[index + 1]), let low = _hexDigit(bytes[index + 2]) {
        decoded.append(high << 4 | low)
        index += 3
      } else {
        decoded.append(bytes[index])
        index += 1
      }
    }
    return normalized(String(decoding: decoded, as: UTF8.self))
  }

  package func file(at path: String) -> Data? {
    let path = Self.normalized(path)
    return lock.withLock { files[path] }
  }

  package func isDirectory(_ path: String) -> Bool {
    let path = Self.normalized(path)
    return lock.withLock { directories.contains(path) }
  }

  package func exists(_ path: String) -> Bool {
    let path = Self.normalized(path)
    return lock.withLock { files[path] != nil || directories.contains(path) }
  }

  /// Creates or replaces the file at `path`; its directory must exist and the path must not be a directory.
  package func writeFile(_ data: Data, at path: String) throws {
    let path = Self.normalized(path)
    let parent = Self.parent(path)
    try lock.withLock {
      guard directories.contains(parent) else { throw FileSystemError(reason: .noSuchFile, path: parent) }
      guard !directories.contains(path) else { throw FileSystemError(reason: .fileExists, path: path) }
      files[path] = data
    }
  }

  /// Appends to the file at `path`, creating it when its directory exists.
  package func appendToFile(_ bytes: some Sequence<UInt8>, at path: String) throws {
    let path = Self.normalized(path)
    try lock.withLock {
      guard directories.contains(Self.parent(path)) else { throw FileSystemError(reason: .noSuchFile, path: Self.parent(path)) }
      // A directory is not a file to append to; writing into it would corrupt the tree.
      guard !directories.contains(path) else { throw FileSystemError(reason: .fileExists, path: path) }
      var data = files[path] ?? Data()
      data.append(contentsOf: bytes)
      files[path] = data
    }
  }

  /// Copies a file to a path that does not exist yet.
  package func copyFile(from source: String, to destination: String) throws {
    let source = Self.normalized(source), destination = Self.normalized(destination)
    try lock.withLock {
      guard let data = files[source] else { throw FileSystemError(reason: .noSuchFile, path: source) }
      guard files[destination] == nil, !directories.contains(destination) else {
        throw FileSystemError(reason: .fileExists, path: destination)
      }
      guard directories.contains(Self.parent(destination)) else {
        throw FileSystemError(reason: .noSuchFile, path: Self.parent(destination))
      }
      files[destination] = data
    }
  }

  package func makeDirectory(_ path: String, intermediate: Bool) throws {
    let path = Self.normalized(path)
    try lock.withLock {
      // Walk up to the nearest existing ancestor first, then create the missing directories top-down. Iterative, so a
      // deep path costs no recursion.
      var missing: [String] = []
      var current = path
      while !directories.contains(current) {
        guard files[current] == nil else { throw FileSystemError(reason: .fileExists, path: current) }
        missing.append(current)
        let parent = Self.parent(current)
        if directories.contains(parent) { break }
        guard intermediate else { throw FileSystemError(reason: .noSuchFile, path: parent) }
        current = parent
      }
      for directory in missing.reversed() { directories.insert(directory) }
    }
  }

  package func remove(_ path: String) throws {
    let path = Self.normalized(path)
    // The root cannot be removed: that would wipe the whole tree.
    guard path != "/" else { throw FileSystemError(reason: .unsupported, path: path) }
    try lock.withLock {
      if files.removeValue(forKey: path) != nil { return }
      guard directories.contains(path) else { throw FileSystemError(reason: .noSuchFile, path: path) }
      let prefix = path == "/" ? "/" : path + "/"
      directories = directories.filter { $0 != path && !$0.hasPrefix(prefix) }
      files = files.filter { !$0.key.hasPrefix(prefix) }
    }
  }

  /// The direct children of a directory, as full paths, sorted.
  package func children(of path: String) -> [String] {
    let path = Self.normalized(path)
    let prefix = path == "/" ? "/" : path + "/"
    return lock.withLock {
      var names: Set<String> = []
      for entry in files.keys where entry.hasPrefix(prefix) && !entry.dropFirst(prefix.count).contains("/") { names.insert(entry) }
      for entry in directories where entry != path && entry.hasPrefix(prefix) && !entry.dropFirst(prefix.count).contains("/") { names.insert(entry) }
      return names.sorted()
    }
  }
}

private func _hexDigit(_ byte: UInt8) -> UInt8? {
  switch byte {
  case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
  case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
  case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
  default: return nil
  }
}
