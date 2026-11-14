// SwiftUIWeb applications have one file system on every host: a virtual one that lives in memory for the life of the
// process (the page, in the browser). Applications that stage files (temporary copies for uploads, cache folders,
// compressed media) use `FileManager`, `Data.write(to:)`, `Data(contentsOf:)` and the well-known directory URLs, which
// all resolve against it. The tree itself is SwiftUIWebTransferable's `_VirtualFileSystem`.
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

extension URL {
  /// The path of a `file://` URL (or a bare path) in the virtual file system.
  var _virtualPath: String { _VirtualFileSystem.path(of: self) }
  static func _file(_ path: String) -> URL { URL("file://" + path) }

  /// The file URL with `.` and `..` resolved; other URLs are returned unchanged.
  public var standardizedFileURL: URL {
    guard isFileURL else { return self }
    return URL._file(_virtualPath)
  }

  public static var temporaryDirectory: URL { _file("/tmp/") }
  public static var documentsDirectory: URL { _file("/Documents/") }
  public static var cachesDirectory: URL { _file("/Library/Caches/") }
  public static var applicationSupportDirectory: URL { _file("/Library/Application Support/") }

  public func appending<S: StringProtocol>(component: S, directoryHint: URL.DirectoryHint = .inferFromPath) -> URL {
    appendingPathComponent(String(component), isDirectory: directoryHint == .isDirectory)
  }
  public func appending<S: StringProtocol>(path: S, directoryHint: URL.DirectoryHint = .inferFromPath) -> URL {
    appendingPathComponent(String(path), isDirectory: directoryHint == .isDirectory)
  }
  public enum DirectoryHint: Sendable { case inferFromPath, isDirectory, notDirectory, checkFileSystem }
}

/// Apple's top-level `URLResourceKey`: the keys `FileManager` reports for a directory entry.
public struct URLResourceKey: Hashable, Sendable {
  public let rawValue: String
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public static let isDirectoryKey = URLResourceKey("isDirectoryKey")
  public static let contentModificationDateKey = URLResourceKey("contentModificationDateKey")
}

public final class FileManager: @unchecked Sendable {
  public static let `default` = FileManager()
  public enum SearchPathDirectory: Sendable { case documentDirectory, cachesDirectory, applicationSupportDirectory, libraryDirectory, desktopDirectory, downloadsDirectory }
  public enum SearchPathDomainMask: Sendable { case userDomainMask, localDomainMask, allDomainsMask }
  public struct DirectoryEnumerationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let skipsHiddenFiles = DirectoryEnumerationOptions(rawValue: 4)
  }

  private var vfs: _VirtualFileSystem { .shared }
  public init() {}

  public var temporaryDirectory: URL { .temporaryDirectory }
  public var currentDirectoryPath: String { "/" }

  public func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
    switch directory {
    case .cachesDirectory: return [.cachesDirectory]
    case .applicationSupportDirectory, .libraryDirectory: return [.applicationSupportDirectory]
    default: return [.documentsDirectory]
    }
  }

  public func url(for directory: FileManager.SearchPathDirectory, in domain: FileManager.SearchPathDomainMask, appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
    let found = urls(for: directory, in: domain)[0]
    if shouldCreate { try createDirectory(at: found, withIntermediateDirectories: true) }
    return found
  }

  public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
    try vfs.makeDirectory(url._virtualPath, intermediate: withIntermediateDirectories)
  }
  public func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws {
    try vfs.makeDirectory(path, intermediate: withIntermediateDirectories)
  }

  public func removeItem(at url: URL) throws { try vfs.remove(url._virtualPath) }
  public func removeItem(atPath path: String) throws { try vfs.remove(path) }

  public func fileExists(atPath path: String) -> Bool { vfs.exists(path) }

  public func copyItem(at source: URL, to destination: URL) throws {
    try vfs.copyFile(from: source._virtualPath, to: destination._virtualPath)
  }

  public func moveItem(at source: URL, to destination: URL) throws {
    try copyItem(at: source, to: destination)
    try removeItem(at: source)
  }

  public func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
    guard vfs.isDirectory(url._virtualPath) else { throw FileSystemError(reason: .noSuchFile, path: url._virtualPath) }
    return vfs.children(of: url._virtualPath).map { URL._file($0) }
  }

  public func contentsOfDirectory(atPath path: String) throws -> [String] {
    guard vfs.isDirectory(path) else { throw FileSystemError(reason: .noSuchFile, path: path) }
    return vfs.children(of: path).map { String($0.split(separator: "/").last ?? "") }
  }

  public func contents(atPath path: String) -> Data? { vfs.file(at: path) }
}

extension Data {
  public struct WritingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let atomic = WritingOptions(rawValue: 1)
  }

  /// Foundation's `Data.ReadingOptions`. The virtual file system holds files in memory, so none of them changes a read.
  public struct ReadingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let mappedIfSafe = ReadingOptions(rawValue: 1)
    public static let uncached = ReadingOptions(rawValue: 2)
    public static let alwaysMapped = ReadingOptions(rawValue: 8)
  }

  public func write(to url: URL, options: Data.WritingOptions = []) throws {
    try _VirtualFileSystem.shared.writeFile(self, at: url._virtualPath)
  }

  /// Reads from the virtual file system; a network URL is not a file and has to go through `URLSession`. A file the
  /// person picked (`fileImporter`, a drop) is a `transfer-file://` URL whose bytes the page already holds, and reads
  /// as Apple's Foundation reads the picked file's URL.
  public init(contentsOf url: URL, options: Data.ReadingOptions = []) throws {
    if let identifier = SwiftUIWebFileRuntime.identifier(from: url) {
      guard let payload = SwiftUIWebTransferRuntime._payloadIfLoaded(identifier: identifier) else {
        throw FileSystemError(reason: .noSuchFile, path: url.absoluteString)
      }
      self = payload.data
      return
    }
    guard url.scheme == nil || url.scheme == "file", let data = _VirtualFileSystem.shared.file(at: url._virtualPath) else {
      throw FileSystemError(reason: .noSuchFile, path: url.absoluteString)
    }
    self = data
  }
}
