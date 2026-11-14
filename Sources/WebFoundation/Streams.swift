// Foundation's `Stream`, `InputStream` and `OutputStream` for browser and Embedded builds. Memory streams are plain
// byte buffers; URL and path streams read and write the same virtual file system as `Data(contentsOf:)` and
// `Data.write(to:)`. Status transitions, return values and errors follow Foundation (checked against it for a
// memory, a buffer and a file stream).
//
// A browser page has no run loop, so `schedule(in:forMode:)` and `remove(from:forMode:)` are accepted and do
// nothing, and a stream never delivers events to its delegate; callers read and write synchronously, as the JSON
// stream APIs do. The network-backed streams (`getStreamsToHost`, bound streams) and `InputStream.getBuffer` are not
// provided.
@_spi(Renderer) import SwiftUIWebTransferable

/// Foundation's run loop. A browser page has no run loop, so this only gives the scheduling APIs a type to name.
open class RunLoop: NSObject, @unchecked Sendable {
  public struct Mode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let `default` = Mode("kCFRunLoopDefaultMode")
    public static let common = Mode("kCFRunLoopCommonModes")
  }

  private static let _shared = RunLoop()
  open class var current: RunLoop { _shared }
  open class var main: RunLoop { _shared }
}

/// Receives the events of a stream scheduled on a run loop. A browser stream has no run loop and never calls it.
public protocol StreamDelegate: NSObjectProtocol {
  func stream(_ aStream: Stream, handle eventCode: Stream.Event)
}

extension StreamDelegate {
  public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {}
}

/// The state shared by input and output streams.
open class Stream: NSObject {
  public struct Event: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let openCompleted = Event(rawValue: 1 << 0)
    public static let hasBytesAvailable = Event(rawValue: 1 << 1)
    public static let hasSpaceAvailable = Event(rawValue: 1 << 2)
    public static let errorOccurred = Event(rawValue: 1 << 3)
    public static let endEncountered = Event(rawValue: 1 << 4)
  }

  public enum Status: UInt, Sendable {
    case notOpen = 0
    case opening = 1
    case open = 2
    case reading = 3
    case writing = 4
    case atEnd = 5
    case closed = 6
    case error = 7
  }

  public struct PropertyKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let socketSecurityLevelKey = PropertyKey(rawValue: "kCFStreamPropertySocketSecurityLevel")
    public static let socksProxyConfigurationKey = PropertyKey(rawValue: "kCFStreamPropertySOCKSProxy")
    public static let dataWrittenToMemoryStreamKey = PropertyKey(rawValue: "kCFStreamPropertyDataWritten")
    public static let fileCurrentOffsetKey = PropertyKey(rawValue: "kCFStreamPropertyFileCurrentOffset")
    public static let networkServiceType = PropertyKey(rawValue: "kCFStreamNetworkServiceType")
  }

  package var _status: Status = .notOpen
  package var _error: NSError?

  unowned(unsafe) open var delegate: (any StreamDelegate)?

  open func open() {}
  open func close() {}
  open func property(forKey key: Stream.PropertyKey) -> Any? { nil }
  open func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }
  open func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
  open func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
  open var streamStatus: Stream.Status { _status }
  open var streamError: (any Error)? { _error }

  package func _fail(domain: String = NSPOSIXErrorDomain, code: Int) {
    _status = .error
    _error = NSError(domain: domain, code: code, userInfo: ["_kCFStreamErrorCodeKey": code, "_kCFStreamErrorDomainKey": 1])
  }
}

extension URL {
  /// A stream opens a file only for a `file:` URL or a bare path; any other scheme is not a file.
  fileprivate var _isStreamFile: Bool { scheme == nil || scheme == "file" }
}

/// A stream that reads bytes from memory or from a file.
open class InputStream: Stream {
  private var _bytes: [UInt8] = []
  private var _position = 0
  private let _path: String?

  public init(data: Data) {
    _bytes = Array(data)
    _path = nil
    super.init()
  }

  public init?(url: URL) {
    guard url._isStreamFile else { return nil }
    _path = url._virtualPath
    super.init()
  }

  public convenience init?(fileAtPath path: String) {
    self.init(url: URL(fileURLWithPath: path))
  }

  open override func open() {
    guard _status == .notOpen else { return }
    if let path = _path {
      if let data = _VirtualFileSystem.shared.file(at: path) {
        _bytes = Array(data)
      } else if !_VirtualFileSystem.shared.isDirectory(path) {
        _fail(code: 2)
        return
      }
    }
    _status = .open
  }

  open override func close() {
    if _status != .notOpen { _status = .closed }
  }

  open func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
    switch _status {
    case .open: break
    case .atEnd: return 0
    default: return -1
    }
    guard len >= 0 else { return -1 }
    let count = min(len, _bytes.count - _position)
    if count > 0 {
      _bytes.withUnsafeBufferPointer { source in
        buffer.update(from: source.baseAddress! + _position, count: count)
      }
      _position += count
    }
    // A memory stream reports the end as soon as the last byte is read; a file stream when a read finds nothing.
    if _position >= _bytes.count && (_path == nil || count == 0) { _status = .atEnd }
    return count
  }

  open var hasBytesAvailable: Bool {
    guard _status == .open else { return false }
    return _path != nil || _position < _bytes.count
  }

  open override func property(forKey key: Stream.PropertyKey) -> Any? {
    if key == .fileCurrentOffsetKey, _path != nil, _status != .notOpen { return _position }
    return nil
  }
}

/// A stream that writes bytes to memory, to a caller's buffer or to a file.
open class OutputStream: Stream {
  private enum Target {
    case memory
    case buffer(UnsafeMutablePointer<UInt8>, Int)
    case file(String, append: Bool)
  }

  private let _target: Target
  private var _written: [UInt8] = []
  private var _offset = 0

  public required init(toMemory: ()) {
    _target = .memory
    super.init()
  }

  public init(toBuffer buffer: UnsafeMutablePointer<UInt8>, capacity: Int) {
    _target = .buffer(buffer, capacity)
    super.init()
  }

  public init?(url: URL, append shouldAppend: Bool) {
    guard url._isStreamFile else { return nil }
    _target = .file(url._virtualPath, append: shouldAppend)
    super.init()
  }

  public convenience init?(toFileAtPath path: String, append shouldAppend: Bool) {
    self.init(url: URL(fileURLWithPath: path), append: shouldAppend)
  }

  open class func toMemory() -> Self { Self(toMemory: ()) }

  open override func open() {
    guard _status == .notOpen else { return }
    if case .file(let path, let append) = _target {
      let vfs = _VirtualFileSystem.shared
      guard vfs.isDirectory(_VirtualFileSystem.parent(path)) else {
        _fail(code: 2)
        return
      }
      let existing = vfs.file(at: path)
      _offset = append ? existing?.count ?? 0 : 0
      if !append || existing == nil { try? vfs.writeFile(Data(), at: path) }
    }
    _status = .open
  }

  open override func close() {
    if _status != .notOpen { _status = .closed }
  }

  open func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
    guard _status == .open, len >= 0 else { return -1 }
    if len == 0 { return 0 }
    switch _target {
    case .memory:
      _written.append(contentsOf: UnsafeBufferPointer(start: buffer, count: len))
    case .buffer(let destination, let capacity):
      // A buffer stream takes a write whole or not at all.
      guard len <= capacity - _offset else {
        _fail(code: 12)
        return -1
      }
      (destination + _offset).update(from: buffer, count: len)
      _offset += len
    case .file(let path, _):
      do {
        try _VirtualFileSystem.shared.appendToFile(UnsafeBufferPointer(start: buffer, count: len), at: path)
      } catch {
        _fail(code: 2)
        return -1
      }
      _offset += len
    }
    return len
  }

  open var hasSpaceAvailable: Bool {
    guard _status == .open else { return false }
    if case .buffer(_, let capacity) = _target { return _offset < capacity }
    return true
  }

  open override func property(forKey key: Stream.PropertyKey) -> Any? {
    if key == .dataWrittenToMemoryStreamKey, case .memory = _target { return Data(_written) }
    if key == .fileCurrentOffsetKey, _status != .notOpen {
      if case .file = _target { return _offset }
    }
    return nil
  }
}
