import Foundation

/// The file-system behavior of the previous lowerer that the driver reproduces: paths are kept as the text they were given
/// in (a workspace path is joined to the working directory and never normalized, because the report prints it), `fs::canonicalize`
/// is `realpath` (Foundation's `resolvingSymlinksInPath` drops `/private`), a source is read as UTF-8 and nothing else,
/// and a failure reads like `No such file or directory (os error 2)`.
enum FileSystem {
  /// `strerror` and the errno, the text of an error made from an OS error.
  static func osError(_ code: Int32 = errno) -> String {
    "\(String(cString: strerror(code))) (os error \(code))"
  }

  /// `fs::canonicalize`.
  static func canonical(_ path: String) throws -> String {
    guard let resolved = realpath(path, nil) else { throw LoweringArguments.Failure.message(osError()) }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// `Path::join`: an absolute `component` replaces the base; otherwise it is appended after a single separator.
  static func join(_ base: String, _ component: String) -> String {
    if component.hasPrefix("/") { return component }
    if base.isEmpty { return component }
    return base.hasSuffix("/") ? base + component : base + "/" + component
  }

  /// `Path::parent`: the path without its last component.
  static func parent(of path: String) -> String? {
    var trimmed = Substring(path)
    while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
    guard trimmed != "/", let slash = trimmed.lastIndex(of: "/") else { return trimmed.isEmpty ? nil : "" }
    return slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
  }

  /// The last component of a path (`Path::file_name`), without a trailing separator.
  static func lastComponent(of path: String) -> String {
    var trimmed = Substring(path)
    while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
    guard let slash = trimmed.lastIndex(of: "/") else { return String(trimmed) }
    return String(trimmed[trimmed.index(after: slash)...])
  }

  /// A relative path made absolute against the working directory, as the previous lowerer does for `--workspace`.
  static func absolute(_ path: String) -> String {
    path.hasPrefix("/") ? path : join(FileManager.default.currentDirectoryPath, path)
  }

  static func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  /// A directory itself, not a symbolic link to one: a walk never enters a link, and a removal removes the link alone.
  static func isDirectory(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
  }

  /// Whether anything is at `path`, a dangling symbolic link included (`exists` follows the link and misses it).
  static func existsWithoutFollowing(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
  }

  static func isSymbolicLink(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
  }

  /// A symbolic link whose target is a directory. A copy of a package follows it (the copy holds what it names), unlike a
  /// removal or a write.
  static func isLinkToDirectory(_ path: String) -> Bool {
    var info = stat()
    return isSymbolicLink(path) && stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
  }

  /// Whether a `.swift` file lies below `path` (links followed, as a copy would read them; at most 100,000 entries).
  static func containsSwiftFile(_ path: String) -> Bool {
    guard let walk = FileManager.default.enumerator(atPath: path) else { return false }
    var seen = 0
    while let entry = walk.nextObject() as? String, seen < 100_000 {
      if entry.hasSuffix(".swift") { return true }
      seen += 1
    }
    return false
  }

  /// Whether a component of `relative` below `root` is a symbolic link (`root` itself is not checked).
  static func hasSymbolicLinkComponent(root: String, relative: String) -> Bool {
    var path = root
    for component in relative.split(separator: "/") {
      path = join(path, String(component))
      if isSymbolicLink(path) { return true }
    }
    return false
  }

  /// Removes a symbolic link at `path` (the link only), so that a write creates a file there instead of writing through the
  /// link into its target.
  static func removeSymbolicLink(_ path: String) throws {
    guard isSymbolicLink(path) else { return }
    do {
      try FileManager.default.removeItem(atPath: path)
    } catch {
      throw LoweringArguments.Failure.message("remove \(path): \(describe(error))")
    }
  }

  /// Reports an entry of a package that is not lowered or copied because it is a symbolic link. A link is never followed:
  /// it could point outside the package.
  static func skipSymbolicLink(_ path: String) {
    FileHandle.standardError.write(Data("note: skipped symbolic link \(path)\n".utf8))
  }

  /// `fs::read_to_string`.
  static func readString(_ path: String) throws -> String {
    guard let data = FileManager.default.contents(atPath: path) else {
      throw LoweringArguments.Failure.message(osError(isDirectory(path) ? EISDIR : (exists(path) ? EACCES : ENOENT)))
    }
    let text = String(decoding: data, as: UTF8.self)
    // Invalid bytes decode to U+FFFD, so the text only encodes back to the same bytes when the file was valid UTF-8.
    guard text.utf8.elementsEqual(data) else {
      throw LoweringArguments.Failure.message("stream did not contain valid UTF-8")
    }
    return text
  }

  /// `fs::create_dir_all`.
  static func createDirectories(_ path: String, context: String? = nil) throws {
    do {
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    } catch {
      throw LoweringArguments.Failure.message("\(context.map { "\($0): " } ?? "")\(describe(error))")
    }
  }

  /// `fs::write`: truncates and writes in place, so the permissions of an existing file are kept.
  static func write(_ text: String, to path: String) throws {
    try write(Data(text.utf8), to: path)
  }

  /// Writes `text` unless the file already holds exactly these bytes, so an unchanged file keeps its modification time.
  /// The size is compared first. A directory in the way is removed. Returns whether the file was written.
  @discardableResult
  static func writeIfChanged(_ text: String, to path: String) throws -> Bool {
    let data = Data(text.utf8)
    try removeSymbolicLink(path)
    if isDirectory(path) { try removeStale(path) }
    if exists(path), let size = fileSize(path), size == data.count, FileManager.default.contents(atPath: path) == data {
      return false
    }
    try write(data, to: path)
    return true
  }

  /// `copy`, unless the destination already holds the source's bytes (size first, then contents). The permissions are
  /// set only when the file is written. Returns whether it was written.
  @discardableResult
  static func copyIfChanged(from source: String, to destination: String) throws -> Bool {
    // Most files of a mirror did not change since the last run, and reading both copies of each is most of an unchanged
    // run's time. A destination that was last touched after the source last changed (its contents or its attributes), with
    // the same size, is the copy made then: nothing is read.
    if unchangedSinceCopied(source: source, destination: destination) { return false }
    // The contents are read through a symbolic link too (`copy` follows it), so the size is that of the bytes read: the
    // attributes of a link are the size of its target path.
    guard let data = FileManager.default.contents(atPath: source) else {
      try copy(from: source, to: destination)
      return true
    }
    try removeSymbolicLink(destination)
    if isDirectory(destination) { try removeStale(destination) }
    if exists(destination), fileSize(destination) == data.count, FileManager.default.contents(atPath: destination) == data {
      return false
    }
    try copy(from: source, to: destination)
    return true
  }

  /// Whether `destination` is known to hold `source`'s bytes without reading them: both are regular files of the same
  /// size, the source was not modified after the destination, and the source's last status change (which every write,
  /// rename over it or attribute change moves, and which cannot be set back) is older than the destination's. A copy keeps
  /// the source's modification time, so the two modification times are usually equal.
  static func unchangedSinceCopied(source: String, destination: String) -> Bool {
    var from = stat(), to = stat()
    guard lstat(source, &from) == 0, lstat(destination, &to) == 0 else { return false }
    guard (from.st_mode & S_IFMT) == S_IFREG, (to.st_mode & S_IFMT) == S_IFREG, from.st_size == to.st_size else { return false }
    #if canImport(Darwin)
    let sourceModified = (from.st_mtimespec.tv_sec, from.st_mtimespec.tv_nsec), sourceChanged = (from.st_ctimespec.tv_sec, from.st_ctimespec.tv_nsec)
    let copyModified = (to.st_mtimespec.tv_sec, to.st_mtimespec.tv_nsec), copyChanged = (to.st_ctimespec.tv_sec, to.st_ctimespec.tv_nsec)
    #else
    let sourceModified = (from.st_mtim.tv_sec, from.st_mtim.tv_nsec), sourceChanged = (from.st_ctim.tv_sec, from.st_ctim.tv_nsec)
    let copyModified = (to.st_mtim.tv_sec, to.st_mtim.tv_nsec), copyChanged = (to.st_ctim.tv_sec, to.st_ctim.tv_nsec)
    #endif
    return sourceModified <= copyModified && sourceChanged < copyChanged
  }

  /// The size of a regular file in bytes.
  static func fileSize(_ path: String) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
  }

  /// Gives `destination` the permissions of `source`.
  static func copyPermissions(from source: String, to destination: String) {
    if let attributes = try? FileManager.default.attributesOfItem(atPath: source), let permissions = attributes[.posixPermissions] {
      try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination)
    }
  }

  /// Removes an entry the source no longer has. Entries named like the generated folders (`.build`, ...) are kept, and so
  /// is a directory that holds one of them. Returns whether anything is left at `path`.
  @discardableResult
  static func removeStale(_ path: String, keeping generated: Set<String> = []) throws -> Bool {
    guard isDirectory(path) else {
      do {
        try FileManager.default.removeItem(atPath: path)
      } catch {
        throw LoweringArguments.Failure.message("remove \(path): \(describe(error))")
      }
      return false
    }
    var keptAny = try entries(of: path, context: "read").contains { generated.contains($0) }
    for name in try entries(of: path, context: "read") where !generated.contains(name) {
      if try removeStale(join(path, name), keeping: generated) { keptAny = true }
    }
    if !keptAny {
      do {
        try FileManager.default.removeItem(atPath: path)
      } catch {
        throw LoweringArguments.Failure.message("remove \(path): \(describe(error))")
      }
    }
    return keptAny
  }

  /// How many entries `removeStale(path, keeping:)` removes: each file below `path` that is not under a `generated` name,
  /// and a directory with none of them counts once (so an empty directory is a change too).
  static func removedCount(_ path: String, keeping generated: Set<String> = []) -> Int {
    guard isDirectory(path) else { return 1 }
    let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    var count = 0
    for name in names where !generated.contains(name) { count += removedCount(join(path, name), keeping: generated) }
    return max(count, 1)
  }

  static func write(_ data: Data, to path: String) throws {
    try removeSymbolicLink(path)
    do {
      try data.write(to: URL(fileURLWithPath: path))
    } catch {
      throw LoweringArguments.Failure.message(describe(error))
    }
  }

  /// `fs::copy`: the contents and the permissions, following a symbolic link.
  static func copy(from source: String, to destination: String) throws {
    guard let data = FileManager.default.contents(atPath: source) else {
      throw LoweringArguments.Failure.message("copy \(source) to \(destination): \(osError(exists(source) ? EACCES : ENOENT))")
    }
    try removeSymbolicLink(destination)
    do {
      try data.write(to: URL(fileURLWithPath: destination))
    } catch {
      throw LoweringArguments.Failure.message("copy \(source) to \(destination): \(describe(error))")
    }
    if let attributes = try? FileManager.default.attributesOfItem(atPath: source), let permissions = attributes[.posixPermissions] {
      try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination)
    }
  }

  /// The entries of a directory, or the error of `read_dir`.
  static func entries(of path: String, context: String) throws -> [String] {
    do {
      return try FileManager.default.contentsOfDirectory(atPath: path)
    } catch {
      throw LoweringArguments.Failure.message("\(context) \(path): \(describe(error))")
    }
  }

  /// A Foundation error as the OS error it wraps, in that form.
  static func describe(_ error: Error) -> String {
    let nsError = error as NSError
    if let code = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code, nsError.domain == NSCocoaErrorDomain {
      return osError(Int32(code))
    }
    if nsError.domain == NSPOSIXErrorDomain { return osError(Int32(nsError.code)) }
    switch nsError.code {
    case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return osError(ENOENT)
    case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return osError(EACCES)
    default: return "\(error)"
    }
  }

  /// `Path` ordering: component by component, each compared as bytes. `a.swift` sorts after `a/b.swift`, which a
  /// comparison of the whole strings does not give.
  static func pathPrecedes(_ lhs: String, _ rhs: String) -> Bool {
    let left = lhs.split(separator: "/", omittingEmptySubsequences: true).map { Array($0.utf8) }
    let right = rhs.split(separator: "/", omittingEmptySubsequences: true).map { Array($0.utf8) }
    for (a, b) in zip(left, right) where a != b { return a.lexicographicallyPrecedes(b) }
    return left.count < right.count
  }
}
