import CSwiftUIWebBrowserIO
@_spi(Renderer) import SwiftUIWebLocking

/// Installs the Embedded Swift concurrency hooks in the single BrowserIO C
/// runtime instance. Kept internal to the framework; applications never need
/// to know how the browser event loop is integrated.
public func _swiftUIWebInstallConcurrencyHooks(_ global: UnsafeMutableRawPointer?, _ delayed: UnsafeMutableRawPointer?, _ main: UnsafeMutableRawPointer?) {
  browser_io_install_concurrency_hooks(global, delayed, main)
}

/// Makes the runtime's `MainActor` executor the browser executor, so a job the
/// host drains is already "on" the main actor and never hops back to it.
public func _swiftUIWebInstallMainExecutorGetter(_ getter: UnsafeMutableRawPointer?, checkIsolated: UnsafeMutableRawPointer?, isIsolating: UnsafeMutableRawPointer?, isOnExecutor: UnsafeMutableRawPointer?, isMainExecutor: UnsafeMutableRawPointer?) {
  browser_io_install_main_executor_getter(getter, checkIsolated, isIsolating, isOnExecutor, isMainExecutor)
}

/// The monotonic clock of this runtime, in seconds. It is the WASI monotonic clock in the browser, which a move from the
/// Worker to the main thread keeps continuous. Framework-internal.
public func _swiftUIWebMonotonicSeconds() -> Double { Double(browser_io_monotonic_nanoseconds()) / 1_000_000_000 }

/// The wall clock of this runtime, in milliseconds since the epoch (the host's `Date.now()` in the browser): the one
/// clock the page and the Worker share, which is how a sample taken on one thread is aged on the other. Framework-internal.
public func _swiftUIWebWallClockMilliseconds() -> Double { browser_io_wall_time_seconds() * 1000 }

/// Browser host operations use the browser's main thread. No Foundation or JSKit types cross the ABI.
public struct BrowserIOError: Error, Equatable, Sendable {
  public let code: Int32
  public let message: String
  public init(code: Int32, message: String) { self.code = code; self.message = message }
}

public final class BrowserIOOperation: Sendable {
  public let identifier: UInt32
  private let cancelledFlag = _Locked(false)
  fileprivate init(_ id: UInt32) { identifier = id }
  public var isCancelled: Bool { cancelledFlag.withLock { $0 } }
  public func cancel() {
    let alreadyCancelled = cancelledFlag.withLock { flag -> Bool in
      let previous = flag
      flag = true
      return previous
    }
    guard !alreadyCancelled else { return }
    browser_io_cancel_request(identifier)
  }
}

struct IOWriter {
  var bytes: [UInt8] = []
  mutating func u32(_ value: UInt32) {
    bytes.append(UInt8(truncatingIfNeeded: value)); bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16)); bytes.append(UInt8(truncatingIfNeeded: value >> 24))
  }
  mutating func u64(_ value: UInt64) { u32(UInt32(truncatingIfNeeded: value)); u32(UInt32(truncatingIfNeeded: value >> 32)) }
  mutating func f64(_ value: Double) { u64(value.bitPattern) }
  mutating func data(_ value: [UInt8]) { u32(UInt32(value.count)); bytes.append(contentsOf: value) }
  mutating func text(_ value: String) { data(Array(value.utf8)) }
}
struct IOReader {
  let bytes: [UInt8]
  var offset = 0
  var error: BrowserIOError?
  mutating func u32() -> UInt32 {
    guard error == nil else { return 0 }
    guard offset <= bytes.count, bytes.count - offset >= 4 else { error = BrowserIOError(code: -8, message: "Truncated browser host response"); return 0 }
    let i = offset; offset += 4
    return UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
  }
  mutating func u64() -> UInt64 { UInt64(u32()) | (UInt64(u32()) << 32) }
  mutating func f64() -> Double { Double(bitPattern: u64()) }
  mutating func data() -> [UInt8] {
    let count = Int(exactly: u32()) ?? Int.max
    guard error == nil else { return [] }
    guard offset <= bytes.count, count >= 0, count <= bytes.count - offset else {
      error = BrowserIOError(code: -8, message: "Invalid browser host response length")
      return []
    }
    let result = Array(bytes[offset ..< offset + count]); offset += count; return result
  }
  mutating func text() -> String { String(decoding: data(), as: UTF8.self) }
  mutating func finish() -> BrowserIOError? {
    if let error { return error }
    guard offset == bytes.count else { return BrowserIOError(code: -8, message: "Trailing browser host response bytes") }
    return nil
  }
}

private func ioReceive(_ id: UInt32, _ status: Int32, _ pointer: UnsafePointer<UInt8>?, _ count: UInt32) {
  let body = pointer.map { Array(UnsafeBufferPointer(start: $0, count: Int(count))) } ?? []
  let callback = IORuntime.state.withLock { state -> ((Int32, [UInt8]) -> Void)? in
    status < 100 ? state.pending.removeValue(forKey: id) : state.pending[id]
  }
  callback?(status, body)
}

public func _swiftUIWebReceiveIO(_ id: UInt32, _ status: Int32, _ pointer: UnsafePointer<UInt8>?, _ count: UInt32) {
  ioReceive(id, status, pointer, count)
}
enum IORuntime {
  struct State {
    var pending: [UInt32: (Int32, [UInt8]) -> Void] = .init()
    var nextID: UInt32 = 1
  }
  static let state = _Locked(State())
  static func error(_ status: Int32, _ bytes: [UInt8]) -> BrowserIOError {
    BrowserIOError(code: status, message: String(decoding: bytes, as: UTF8.self))
  }
  static func send(_ operation: UInt32, _ writer: IOWriter, _ callback: @escaping (Int32, [UInt8]) -> Void) -> BrowserIOOperation {
#if arch(wasm32) && hasFeature(Embedded)
    // Embedded browser responses enter through the generated C/WASM export;
    // retaining a Swift closure pointer in that ABI is not supported.
#else
    browser_io_set_callback(ioReceive)
#endif
    let id = state.withLock { state -> UInt32 in
      while state.nextID == 0 || state.pending[state.nextID] != nil { state.nextID &+= 1 }
      let id = state.nextID
      state.nextID &+= 1
      state.pending[id] = callback
      return id
    }
    let result = writer.bytes.withUnsafeBufferPointer { browser_io_request(id, operation, $0.baseAddress, UInt32($0.count)) }
    if result != 0 {
      let completion = state.withLock { $0.pending.removeValue(forKey: id) }
      completion?(result, Array("Browser host is not installed".utf8))
    }
    return BrowserIOOperation(id)
  }
  static func sync(_ operation: UInt32, _ writer: IOWriter) throws(BrowserIOError) -> IOReader {
    let handle = writer.bytes.withUnsafeBufferPointer { browser_io_sync_request(operation, $0.baseAddress, UInt32($0.count)) }
    guard handle != 0 else { throw BrowserIOError(code: -7, message: "Browser storage host is unavailable") }
    defer { browser_io_result_release(handle) }
    let count = Int(browser_io_result_length(handle))
    guard count >= 4, count <= 67108864 else { throw BrowserIOError(code: -8, message: "Invalid storage result length") }
    var bytes = [UInt8](repeating: 0, count: count)
    let copied = bytes.withUnsafeMutableBufferPointer { browser_io_result_copy(handle, $0.baseAddress, UInt32($0.count)) }
    guard copied == Int32(count) else { throw BrowserIOError(code: -8, message: "Storage result copy failed") }
    var reader = IOReader(bytes: bytes)
    let status = Int32(bitPattern: reader.u32())
    if status < 0 { throw BrowserIOError(code: status, message: reader.text()) }
    return reader
  }
}

final class _BrowserIOOperationBox: @unchecked Sendable {
  var operation: BrowserIOOperation? {
    didSet { if cancelled { operation?.cancel() } }
  }
  var cancelled = false

  func cancel() {
    cancelled = true
    operation?.cancel()
  }
}

/// Event-loop timers shared by networking, storage and browser lifecycle
/// code. The browser owns the actual timer; Swift only owns a cancellable
/// operation token. This keeps timer callbacks out of application code and
/// makes cancellation deterministic on both native test hosts and Embedded.
public enum BrowserTimer {
  /// The longest wait the browser keeps in one timer (setTimeout holds 2^31 - 1 milliseconds, about 24.8 days); a longer
  /// one is waited in steps of this length, so `Task.sleep(nanoseconds: .max)` waits instead of returning at once.
  static let longestStep = 2_000_000.0

  @discardableResult
  public static func schedule(
    after seconds: Double,
    _ callback: @escaping @Sendable () -> Void
  ) -> BrowserIOOperation {
    let delay = seconds.isFinite ? max(0, seconds) : 0
    guard delay > longestStep else { return single(after: delay, callback) }
    // The first step stands for the whole wait: cancelling it also stops the steps after it.
    let head = _BrowserIOOperationBox()
    let first = single(after: longestStep) {
      guard let operation = head.operation, !operation.isCancelled else { return }
      schedule(after: delay - longestStep) {
        guard let operation = head.operation, !operation.isCancelled else { return }
        callback()
      }
    }
    head.operation = first
    return first
  }

  private static func single(after delay: Double, _ callback: @escaping @Sendable () -> Void) -> BrowserIOOperation {
    var writer = IOWriter()
    writer.f64(delay)
    return IORuntime.send(_BrowserIOProtocol.timer, writer) { status, _ in
      if status == 0 { callback() }
    }
  }

  public static func sleep(for seconds: Double) async throws {
    var left = seconds.isFinite ? max(0, seconds) : 0
    repeat {
      let step = min(left, longestStep)
      try await sleepOnce(for: step)
      left -= step
    } while left > 0
  }

  private static func sleepOnce(for delay: Double) async throws {
    let box = _BrowserIOOperationBox()
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        var writer = IOWriter()
        writer.f64(delay)
        box.operation = IORuntime.send(_BrowserIOProtocol.timer, writer) { status, bytes in
          if status == 0 { continuation.resume() }
          else { continuation.resume(throwing: IORuntime.error(status, bytes)) }
        }
      }
    }, onCancel: {
      box.cancel()
    })
  }
}

public struct BrowserHTTPRequest: Sendable {
  public var url: String
  public var method: String
  public var headers: [String: String]
  public var body: [UInt8]?
  public var timeoutMilliseconds: UInt32
  public var maximumResponseBytes: UInt32
  public var credentials: Credentials
  public var redirect: Redirect
  public var cache: Cache
  public enum Credentials: String, Sendable { case omit, sameOrigin = "same-origin", include }
  public enum Redirect: String, Sendable { case follow, manual, error }
  /// The browser's HTTP cache mode for the request (the `fetch` `cache` option).
  public enum Cache: String, Sendable {
    case `default`
    case noStore = "no-store"
    case reload
    case noCache = "no-cache"
  }
  public init(url: String, method: String = "GET", headers: [String: String] = .init(), body: [UInt8]? = nil,
              timeoutMilliseconds: UInt32 = 30000, maximumResponseBytes: UInt32 = 16777216,
              credentials: Credentials = .sameOrigin, redirect: Redirect = .follow, cache: Cache = .default) {
    self.url = url; self.method = method; self.headers = headers; self.body = body
    self.timeoutMilliseconds = timeoutMilliseconds; self.maximumResponseBytes = maximumResponseBytes; self.credentials = credentials; self.redirect = redirect
    self.cache = cache
  }
  /// The packet's mode word: bit 0 streams the response, bit 1 asks the host for request-body progress
  /// (`fetchUploadProgress` events, honored only by the non-streaming XHR path), and bit 2 asks for the buffered
  /// response's download progress (`fetchDownloadProgress` events). A streamed response needs no download events:
  /// its chunks already cross the bridge, and Swift counts them.
  fileprivate func wire(stream: Bool, uploadProgress: Bool = false, downloadProgress: Bool = false) -> IOWriter {
    var out = IOWriter(); out.text(url); out.text(method); out.text(credentials.rawValue); out.text(redirect.rawValue)
    out.u32(timeoutMilliseconds); out.u32(maximumResponseBytes)
    out.u32((stream ? 1 : 0) | (uploadProgress ? 2 : 0) | (downloadProgress ? 4 : 0))
    out.u32(UInt32(headers.count)); for (key, value) in headers { out.text(key); out.text(value) }
    out.u32(body == nil ? 0 : 1); out.data(body ?? [])
    // Appended last: the host reads it only when bytes remain, so a packet without it keeps the default cache mode.
    out.text(cache.rawValue); return out
  }
}
public struct BrowserHTTPResponse: Sendable {
  public let statusCode: Int
  public let url: String
  public let headers: [String: String]
  public let body: [UInt8]
  public var text: String { String(decoding: body, as: UTF8.self) }
  fileprivate static func read(_ bytes: [UInt8], hasBody: Bool) -> Result<BrowserHTTPResponse, BrowserIOError> {
    var input = IOReader(bytes: bytes)
    let status = Int(exactly: input.u32()) ?? 0; let url = input.text(); let count = Int(exactly: input.u32()) ?? Int.max
    guard input.error == nil, count <= 1024 else { return .failure(input.error ?? BrowserIOError(code: -8, message: "Too many response headers")) }
    var headers: [String: String] = .init()
    for _ in 0..<count { let key = input.text(); headers[key] = input.text() }
    let body = hasBody ? input.data() : []
    if let error = input.finish() { return .failure(error) }
    return .success(BrowserHTTPResponse(statusCode: status, url: url, headers: headers, body: body))
  }
}
public enum BrowserHTTPStreamEvent: Sendable {
  case response(BrowserHTTPResponse)
  case chunk([UInt8])
  case finished
  case failure(BrowserIOError)
}
/// The host's report on a buffered response while it is read: the bytes read so far, and the response's
/// `Content-Length` and `Content-Encoding` headers as the host can see them (nil when absent or not visible).
public struct BrowserHTTPDownloadProgress: Sendable {
  public let received: UInt64
  public let contentLength: String?
  public let contentEncoding: String?
  public init(received: UInt64, contentLength: String?, contentEncoding: String?) {
    self.received = received; self.contentLength = contentLength; self.contentEncoding = contentEncoding
  }
}

public enum BrowserHTTPClient {
  /// HTTP error statuses are returned as responses. Transport errors use the failure case.
  @discardableResult
  public static func send(_ request: BrowserHTTPRequest,
                          completion: @escaping (Result<BrowserHTTPResponse, BrowserIOError>) -> Void) -> BrowserIOOperation {
    IORuntime.send(_BrowserIOProtocol.fetch, request.wire(stream: false)) { status, bytes in
      if status < 0 { completion(.failure(IORuntime.error(status, bytes))); return }
      completion(BrowserHTTPResponse.read(bytes, hasBody: true))
    }
  }

  /// Like `send(_:completion:)`, and reports request-body progress as the host sends it. Hosts that cannot
  /// observe upload progress complete without calling `uploadProgress`.
  @discardableResult
  public static func send(_ request: BrowserHTTPRequest,
                          uploadProgress: @escaping @Sendable (UInt64, UInt64) -> Void,
                          completion: @escaping (Result<BrowserHTTPResponse, BrowserIOError>) -> Void) -> BrowserIOOperation {
    send(request, uploadProgress: uploadProgress, downloadProgress: nil, completion: completion)
  }

  /// Like `send(_:completion:)`, and reports whichever progress the caller asks for: request-body progress (see
  /// `send(_:uploadProgress:completion:)`) and the buffered response's download progress. Download reports are
  /// throttled by the host, and the last one always reports the whole body.
  @discardableResult
  public static func send(_ request: BrowserHTTPRequest,
                          uploadProgress: (@Sendable (UInt64, UInt64) -> Void)?,
                          downloadProgress: (@Sendable (BrowserHTTPDownloadProgress) -> Void)?,
                          completion: @escaping (Result<BrowserHTTPResponse, BrowserIOError>) -> Void) -> BrowserIOOperation {
    let wire = request.wire(stream: false, uploadProgress: uploadProgress != nil, downloadProgress: downloadProgress != nil)
    return IORuntime.send(_BrowserIOProtocol.fetch, wire) { status, bytes in
      if status == _BrowserIOEvent.fetchUploadProgress {
        var reader = IOReader(bytes: bytes)
        let sent = reader.u64(), total = reader.u64()
        if reader.finish() == nil { uploadProgress?(sent, total) }
        return
      }
      if status == _BrowserIOEvent.fetchDownloadProgress {
        var reader = IOReader(bytes: bytes)
        let received = reader.u64(), length = reader.text(), encoding = reader.text()
        if reader.finish() == nil {
          downloadProgress?(BrowserHTTPDownloadProgress(
            received: received,
            contentLength: length.isEmpty ? nil : length,
            contentEncoding: encoding.isEmpty ? nil : encoding
          ))
        }
        return
      }
      if status < 0 { completion(.failure(IORuntime.error(status, bytes))); return }
      completion(BrowserHTTPResponse.read(bytes, hasBody: true))
    }
  }

  /// Async/await form of `send(_:uploadProgress:completion:)`.
  public static func send(_ request: BrowserHTTPRequest,
                          uploadProgress: @escaping @Sendable (UInt64, UInt64) -> Void) async throws -> BrowserHTTPResponse {
    try await send(request, uploadProgress: uploadProgress, downloadProgress: nil)
  }

  /// Async/await form of `send(_:uploadProgress:downloadProgress:completion:)`.
  public static func send(_ request: BrowserHTTPRequest,
                          uploadProgress: (@Sendable (UInt64, UInt64) -> Void)?,
                          downloadProgress: (@Sendable (BrowserHTTPDownloadProgress) -> Void)?) async throws -> BrowserHTTPResponse {
    let box = _BrowserIOOperationBox()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BrowserHTTPResponse, Error>) in
        box.operation = send(request, uploadProgress: uploadProgress, downloadProgress: downloadProgress) { result in continuation.resume(with: result) }
      }
    }, onCancel: {
      box.cancel()
    })
  }

  /// Async/await transport used by the platform-neutral networking façade.
  /// The callback overload remains available for low-level host integrations,
  /// but application code never needs to retain a BrowserIO operation.
  public static func send(_ request: BrowserHTTPRequest) async throws -> BrowserHTTPResponse {
    let box = _BrowserIOOperationBox()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BrowserHTTPResponse, Error>) in
        box.operation = send(request) { result in continuation.resume(with: result) }
      }
    }, onCancel: {
      box.cancel()
    })
  }
  /// Chunks are delivered serially; the host reads the next chunk after the callback returns.
  @discardableResult
  public static func stream(_ request: BrowserHTTPRequest,
                            receive: @escaping (BrowserHTTPStreamEvent) -> Void) -> BrowserIOOperation {
    IORuntime.send(_BrowserIOProtocol.fetch, request.wire(stream: true)) { status, bytes in
      if status < 0 { receive(.failure(IORuntime.error(status, bytes))); return }
      if status == _BrowserIOEvent.fetchChunk { receive(.chunk(bytes)); return }
      if status == 0 { receive(.finished); return }
      switch BrowserHTTPResponse.read(bytes, hasBody: false) {
      case .success(let response): receive(.response(response))
      case .failure(let error): receive(.failure(error))
      }
    }
  }

  /// Async stream variant. Cancellation terminates the host reader and the
  /// stream's termination hook releases any retained operation token.
  public static func stream(_ request: BrowserHTTPRequest) async throws -> (BrowserHTTPResponse, AsyncThrowingStream<[UInt8], Error>) {
    let box = _BrowserIOOperationBox()
    let streamBox = _BrowserIOStreamBox()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (ready: CheckedContinuation<(BrowserHTTPResponse, AsyncThrowingStream<[UInt8], Error>), Error>) in
        streamBox.ready = ready
        let outputStream = AsyncThrowingStream<[UInt8], Error> { continuation in
          streamBox.continuation = continuation
          continuation.onTermination = { _ in box.cancel() }
        }
        box.operation = BrowserHTTPClient.stream(request) { event in
          switch event {
          case .response(let response):
            streamBox.ready?.resume(returning: (response, outputStream)); streamBox.ready = nil
          case .chunk(let bytes): streamBox.continuation?.yield(bytes)
          case .finished: streamBox.continuation?.finish()
          case .failure(let error):
            if let ready = streamBox.ready { ready.resume(throwing: error); streamBox.ready = nil }
            else { streamBox.continuation?.finish(throwing: error) }
          }
        }
      }
    }, onCancel: {
      box.cancel()
    })
  }
}

private final class _BrowserIOStreamBox {
  var ready: CheckedContinuation<(BrowserHTTPResponse, AsyncThrowingStream<[UInt8], Error>), Error>?
  var continuation: AsyncThrowingStream<[UInt8], Error>.Continuation?
}

/// Synchronous string storage with a namespace. No silent in-memory fallback is used.
public struct BrowserWebStorage: Sendable {
  public enum Scope: UInt32, Sendable { case local = 0, session = 1 }
  public let scope: Scope
  public let namespace: String
  public init(_ scope: Scope = .local, namespace: String = "swiftuiweb") { self.scope = scope; self.namespace = namespace }
  private func command(_ action: UInt32, key: String = "", value: String = "") -> IOWriter {
    var out = IOWriter(); out.u32(scope.rawValue); out.text(namespace); out.u32(action); out.text(key); out.text(value); return out
  }
  public func get(_ key: String) throws(BrowserIOError) -> String? {
    var input = try IORuntime.sync(_BrowserIOProtocol.storage, command(0, key: key)); let present = input.u32()
    let value: String? = present == 0 ? nil : input.text(); if let error = input.finish() { throw error }; return value
  }
  public func set(_ value: String, forKey key: String) throws(BrowserIOError) { var result = try IORuntime.sync(_BrowserIOProtocol.storage, command(1, key: key, value: value)); if let error = result.finish() { throw error } }
  public func remove(_ key: String) throws(BrowserIOError) { var result = try IORuntime.sync(_BrowserIOProtocol.storage, command(2, key: key)); if let error = result.finish() { throw error } }
  public func removeAll() throws(BrowserIOError) { var result = try IORuntime.sync(_BrowserIOProtocol.storage, command(3)); if let error = result.finish() { throw error } }
  public func keys() throws(BrowserIOError) -> [String] {
    var input = try IORuntime.sync(_BrowserIOProtocol.storage, command(4)); let count = Int(exactly: input.u32()) ?? Int.max
    guard count <= 100000 else { throw BrowserIOError(code: -8, message: "Invalid storage key count") }
    var result: [String] = []; for _ in 0..<count { result.append(input.text()) }; if let error = input.finish() { throw error }; return result
  }

  public enum Mutation: Sendable, Equatable {
    case set(key: String, value: String)
    case remove(key: String)
  }

  /// Executes a batch against one Web Storage area. The browser adapter
  /// snapshots affected keys and rolls back on quota/security failure, so the
  /// caller observes an all-or-nothing commit even though Web Storage itself
  /// has no transaction primitive.
  @discardableResult
  public func transaction(
    _ mutations: [Mutation],
    expectedRevision: UInt64? = nil
  ) throws(BrowserIOError) -> UInt64 {
    guard mutations.count <= 100_000 else {
      throw BrowserIOError(code: -1, message: "Too many storage mutations")
    }
    guard mutations.allSatisfy({ mutation in
      switch mutation {
      case .set(let key, _), .remove(let key): return !key.isEmpty && key != "__revision"
      }
    }) else {
      throw BrowserIOError(code: -1, message: "Storage keys must not be empty or reserved")
    }
    var out = IOWriter()
    out.u32(scope.rawValue); out.text(namespace)
    out.u32(expectedRevision == nil ? 0 : 1); out.u64(expectedRevision ?? 0)
    out.u32(UInt32(mutations.count))
    for mutation in mutations {
      switch mutation {
      case .set(let key, let value): out.u32(1); out.text(key); out.text(value)
      case .remove(let key): out.u32(2); out.text(key); out.text("")
      }
    }
    var input = try IORuntime.sync(_BrowserIOProtocol.storageTransaction, out)
    let revision = input.u64()
    if let error = input.finish() { throw error }
    return revision
  }

  public func revision() throws(BrowserIOError) -> UInt64 {
    var out = IOWriter(); out.u32(scope.rawValue); out.text(namespace)
    var input = try IORuntime.sync(_BrowserIOProtocol.storageRevision, out)
    let revision = input.u64()
    if let error = input.finish() { throw error }
    return revision
  }
}

public struct BrowserStorageChange: Sendable {
  public let scope: BrowserWebStorage.Scope
  public let key: String?
}

public extension BrowserWebStorage {
  /// Observes cross-document Web Storage mutations for this namespace. The
  /// browser does not fire `storage` back into the document that performed the
  /// write, matching native Web Storage semantics.
  @discardableResult
  static func observeChanges(namespace: String = "swiftuiweb", _ receive: @escaping (BrowserStorageChange) -> Void) -> BrowserIOOperation {
    var out = IOWriter(); out.text(namespace)
    return IORuntime.send(_BrowserIOProtocol.storageChanges, out) { status, bytes in
      guard status == 100 else { return }
      var input = IOReader(bytes: bytes)
      let rawScope = input.u32()
      let present = input.u32()
      let key: String? = present == 0 ? nil : input.text()
      guard input.finish() == nil, let scope = Scope(rawValue: rawScope) else { return }
      receive(BrowserStorageChange(scope: scope, key: key))
    }
  }
}

/// Opens a window on the page that hosts the application (a sign-in popup). The browser may refuse it when no
/// user gesture is recent enough; the result says whether a window was opened.
public enum BrowserWindow {
  @discardableResult
  public static func open(_ url: String) -> Bool {
    var out = IOWriter(); out.text(url)
    guard var input = try? IORuntime.sync(_BrowserIOProtocol.openWindow, out) else { return false }
    let opened = input.u32()
    guard input.finish() == nil else { return false }
    return opened != 0
  }
}

public enum BrowserConnectivity {
  public static func isOnline() -> Bool? {
    let out = IOWriter()
    guard var input = try? IORuntime.sync(_BrowserIOProtocol.connectivity, out) else { return nil }
    let value = input.u32()
    guard input.finish() == nil else { return nil }
    return value != 0
  }

  @discardableResult
  public static func observe(_ receive: @escaping (Bool) -> Void) -> BrowserIOOperation {
    IORuntime.send(_BrowserIOProtocol.connectivityChanges, IOWriter()) { status, bytes in
      guard status == 100 else { return }
      var input = IOReader(bytes: bytes); let value = input.u32()
      guard input.finish() == nil else { return }
      receive(value != 0)
    }
  }
}

/// Browser-native locale/date formatting. The host owns `Intl` and returns a
/// bounded string; no Foundation or locale database crosses the Embedded ABI.
public enum BrowserIntl {
  public static let customStyle: UInt32 = 10
  @discardableResult
  /// `style` 10 is a custom request: `options` (`name=value;...`) are
  /// appended to the packet and become `Intl.DateTimeFormat` options.
  public static func format(epochSeconds: Double, style: UInt32, locale: String = "",
                            calendar: String = "gregory", offsetSeconds: Int = 0, options: String = "") -> String? {
    guard epochSeconds.isFinite, offsetSeconds >= Int32.min, offsetSeconds <= Int32.max else { return nil }
    var writer = IOWriter()
    writer.f64(epochSeconds); writer.u32(style); writer.text(locale); writer.text(calendar)
    writer.u32(UInt32(bitPattern: Int32(clamping: offsetSeconds)))
    if style == customStyle { writer.text(options) }
    guard var reader = try? IORuntime.sync(_BrowserIOProtocol.intl, writer) else { return nil }
    let present = reader.u32()
    let value = present == 0 ? nil : reader.text()
    return reader.finish() == nil ? value : nil
  }
}

/// Browser-native unit formatting: `Intl.NumberFormat` with a CLDR unit (`style: "unit"`), so the number and the unit
/// name are the locale's. `display` is `short`, `narrow` or `long`. Nil when no host answers or the unit is unknown.
extension BrowserIntl {
  public static func formatUnit(value: Double, identifier: String, display: String, locale: String,
                                maximumFractionDigits: Int) -> String? {
    guard value.isFinite else { return nil }
    var writer = IOWriter()
    writer.f64(value); writer.text(locale); writer.text(identifier); writer.text(display)
    writer.u32(UInt32(max(0, min(20, maximumFractionDigits))))
    guard var reader = try? IORuntime.sync(_BrowserIOProtocol.numberUnit, writer) else { return nil }
    let present = reader.u32()
    let text = present == 0 ? nil : reader.text()
    return reader.finish() == nil ? text : nil
  }
}

/// The browser's own time zone offset at an instant, in seconds east of UTC, DST included. Nil when no host answers.
/// The browser's own time zone and week, read through the host's Intl. Every answer is nil when no host answers.
extension BrowserIntl {
  public static func localOffsetSeconds(epochSeconds: Double) -> Int? {
    guard epochSeconds.isFinite else { return nil }
    var writer = IOWriter()
    writer.f64(epochSeconds)
    guard let reader = try? IORuntime.sync(_BrowserIOProtocol.timeZoneOffset, writer) else { return nil }
    var answer = reader
    return _decodeLocalOffset(&answer)
  }

  /// The browser's IANA time zone name, such as `America/Sao_Paulo`.
  public static func localTimeZoneIdentifier() -> String? {
    guard let reader = try? IORuntime.sync(_BrowserIOProtocol.timeZoneIdentifier, IOWriter()) else { return nil }
    var answer = reader
    return _decodeTimeZoneIdentifier(&answer)
  }

  /// The week of `locale` (an empty tag means the browser's language): Foundation's first weekday (1 = Sunday ... 7 =
  /// Saturday) and minimum days in the first week.
  public static func localWeekInfo(locale: String) -> (firstWeekday: Int, minimumDays: Int)? {
    var writer = IOWriter()
    writer.text(locale)
    guard let reader = try? IORuntime.sync(_BrowserIOProtocol.weekInfo, writer) else { return nil }
    var answer = reader
    return _decodeWeekInfo(&answer)
  }

  // The decoders take the host's response bytes after the status word, so tests can drive them with host-shaped bytes.

  /// Intl's offset is a signed 32-bit count of seconds east of UTC, written with `u32` (two's complement).
  static func _decodeLocalOffset(_ reader: inout IOReader) -> Int? {
    let present = reader.u32()
    let offset = Int(Int32(bitPattern: reader.u32()))
    return reader.finish() == nil && present != 0 ? offset : nil
  }

  static func _decodeTimeZoneIdentifier(_ reader: inout IOReader) -> String? {
    let present = reader.u32()
    let name = present == 0 ? nil : reader.text()
    return reader.finish() == nil ? name : nil
  }

  /// Intl's `firstDay` counts from Monday (1) to Sunday (7); Foundation counts from Sunday (1) to Saturday (7).
  /// `minimalDays` outside 1...7 is not a week, so it falls back to 1.
  static func _decodeWeekInfo(_ reader: inout IOReader) -> (firstWeekday: Int, minimumDays: Int)? {
    let present = reader.u32()
    let firstDay = Int(exactly: reader.u32()) ?? 0
    let minimalDays = Int(exactly: reader.u32()) ?? 0
    guard reader.finish() == nil, present != 0, (1...7).contains(firstDay) else { return nil }
    return (firstWeekday: firstDay % 7 + 1, minimumDays: (1...7).contains(minimalDays) ? minimalDays : 1)
  }
}

/// The browser's console (`console.debug`, `info`, `log`, `warn`, `error`), for OSLog's `Logger` (WebOSLog).
public enum BrowserConsole {
  public enum Level: UInt32, Sendable { case debug = 0, info, log, warning, error }

  /// Writes `text` at `level`. False when no browser host answers (a native build, a test).
  @discardableResult
  public static func write(_ text: String, level: Level) -> Bool {
    var writer = IOWriter()
    writer.u32(level.rawValue); writer.text(text)
    guard var reader = try? IORuntime.sync(_BrowserIOProtocol.console, writer) else { return false }
    return reader.finish() == nil
  }
}

/// Opaque DOM handle used by the Embedded browser runtime. The numeric value
/// is owned by the JavaScript host and is stable for the lifetime of a DOM node.
public struct BrowserDOMElement: Equatable, Hashable, Sendable {
  public let identifier: UInt32
  public init(identifier: UInt32) { self.identifier = identifier }
}

public struct BrowserDOMMount: Sendable {
  public let element: BrowserDOMElement
  public let key: String
  public let token: String
}

/// Minimal synchronous DOM bridge for Embedded Swift. It intentionally moves
/// object identity and DOM access into the browser host instead of recreating
/// a dynamic JavaScript object model in Swift.
public enum BrowserDOMBridge {
  private static func command(_ action: UInt32, element: BrowserDOMElement? = nil, name: String = "", value: String = "") -> IOWriter {
    var out = IOWriter(); out.u32(action); out.u32(element?.identifier ?? 0); out.text(name); out.text(value); return out
  }
  private static func result(_ action: UInt32, element: BrowserDOMElement? = nil, name: String = "", value: String = "") throws(BrowserIOError) -> IOReader {
    try IORuntime.sync(_BrowserIOProtocol.dom, command(action, element: element, name: name, value: value))
  }
  public static func mounts() throws(BrowserIOError) -> [BrowserDOMMount] {
    var input = try result(0); let count = Int(exactly: input.u32()) ?? Int.max
    guard count <= 100000 else { throw BrowserIOError(code: -8, message: "Invalid WebMount count") }
    var mounts: [BrowserDOMMount] = []; mounts.reserveCapacity(count)
    for _ in 0..<count { mounts.append(BrowserDOMMount(element: .init(identifier: input.u32()), key: input.text(), token: input.text())) }
    if let error = input.finish() { throw error }; return mounts
  }
  public static func isConnected(_ element: BrowserDOMElement) -> Bool { guard var input = try? result(1, element: element) else { return false }; return input.u32() != 0 }
  public static func attribute(_ name: String, of element: BrowserDOMElement) -> String? {
    guard var input = try? result(2, element: element, name: name) else { return nil }
    let present = input.u32(); return present == 0 ? nil : input.text()
  }
  public static func setAttribute(_ name: String, value: String, on element: BrowserDOMElement) { _ = try? result(3, element: element, name: name, value: value) }
  public static func removeAttribute(_ name: String, from element: BrowserDOMElement) { _ = try? result(4, element: element, name: name) }
  public static func value(of element: BrowserDOMElement) -> String? {
    guard var input = try? result(8, element: element) else { return nil }; let present=input.u32(); return present == 0 ? nil : input.text()
  }
  public static func setValue(_ value: String, on element: BrowserDOMElement) { _ = try? result(5, element: element, value: value) }
  public static func textContent(of element: BrowserDOMElement) -> String? {
    guard var input = try? result(6, element: element) else { return nil }; let present=input.u32(); return present == 0 ? nil : input.text()
  }
  public static func setTextContent(_ value: String, on element: BrowserDOMElement) { _ = try? result(7, element: element, value: value) }
  /// Mounts the page's registered DOM component `component` in `element` with its initial `state`.
  /// The host owns the ShadowRoot, the instance and its cleanup. A component the page has not
  /// defined yet mounts when it is defined; a failure the host can only see later is reported there.
  public static func domViewMount(component: String, state: String, on element: BrowserDOMElement) {
    domView(9, name: component, value: state, on: element)
  }
  /// Passes a changed `state` to the component mounted in `element`.
  public static func domViewUpdate(state: String, on element: BrowserDOMElement) {
    domView(11, name: "", value: state, on: element)
  }
  /// Disposes the component mounted in `element` (or cancels its pending mount).
  public static func domViewUnmount(on element: BrowserDOMElement) {
    domView(12, name: "", value: "", on: element)
  }
  private static func domView(_ action: UInt32, name: String, value: String, on element: BrowserDOMElement) {
    do { _ = try result(action, element: element, name: name, value: value) }
    catch { report(error.message, on: element) }
  }
  /// Surfaces a failed WebMount or DOMView operation in the host: a console error and a
  /// `data-dom-view-error` attribute on the element (the app root when `element` is nil).
  /// Failures are never dropped silently.
  package static func report(_ message: String, on element: BrowserDOMElement? = nil) {
    _ = try? result(10, element: element, name: "", value: message)
  }
  public static func isSameNode(_ lhs: BrowserDOMElement, _ rhs: BrowserDOMElement) -> Bool { lhs == rhs }
}


/// HTMLMediaElement bridge for Embedded WASM. Media state stays in the browser;
/// Swift exchanges only the opaque DOM handle and primitive values.
public enum BrowserMediaBridge {
  private static func command(_ action: UInt32, element: BrowserDOMElement, text: String = "", number: Double = 0, flag: Bool = false) -> IOWriter {
    var out = IOWriter(); out.u32(action); out.u32(element.identifier); out.text(text); out.f64(number); out.u32(flag ? 1 : 0); return out
  }
  private static func result(_ action: UInt32, element: BrowserDOMElement, text: String = "", number: Double = 0, flag: Bool = false) throws(BrowserIOError) -> IOReader {
    do { return try IORuntime.sync(_BrowserIOProtocol.media, command(action, element: element, text: text, number: number, flag: flag)) }
    catch {
      // Status -7: the host cannot serve media in this runtime. Callers keep their defaults, but the
      // failure is surfaced on the element rather than dropped.
      if error.code == -7 { BrowserDOMBridge.report(error.message, on: element) }
      throw error
    }
  }
  public static func currentTime(_ e: BrowserDOMElement) -> Double { guard var r = try? result(0, element:e) else { return 0 }; return r.f64() }
  public static func setCurrentTime(_ v: Double, _ e: BrowserDOMElement) { _ = try? result(1, element:e, number:v) }
  public static func duration(_ e: BrowserDOMElement) -> Double { guard var r = try? result(2, element:e) else { return .nan }; return r.f64() }
  public static func rate(_ e: BrowserDOMElement) -> Double { guard var r = try? result(3, element:e) else { return 1 }; return r.f64() }
  public static func setRate(_ v: Double, _ e: BrowserDOMElement) { _ = try? result(4, element:e, number:v) }
  public static func volume(_ e: BrowserDOMElement) -> Double { guard var r = try? result(5, element:e) else { return 1 }; return r.f64() }
  public static func setVolume(_ v: Double, _ e: BrowserDOMElement) { _ = try? result(6, element:e, number:v) }
  public static func muted(_ e: BrowserDOMElement) -> Bool { guard var r = try? result(7, element:e) else { return false }; return r.u32() != 0 }
  public static func setMuted(_ v: Bool, _ e: BrowserDOMElement) { _ = try? result(8, element:e, flag:v) }
  public static func play(_ e: BrowserDOMElement) { _ = try? result(9, element:e) }
  public static func pause(_ e: BrowserDOMElement) { _ = try? result(10, element:e) }
  public static func setSource(_ source: String, _ e: BrowserDOMElement) { _ = try? result(11, element:e, text:source) }
  public static func canPlay(_ mime: String, _ e: BrowserDOMElement) -> Bool { guard var r = try? result(12, element:e, text:mime) else { return false }; return r.u32() != 0 }
  public static func readyState(_ e: BrowserDOMElement) -> Int { guard var r = try? result(13, element:e) else { return 0 }; return Int(exactly: r.u32()) ?? 0 }
  public static func networkState(_ e: BrowserDOMElement) -> Int { guard var r = try? result(14, element:e) else { return 0 }; return Int(exactly: r.u32()) ?? 0 }
  public static func buffered(_ e: BrowserDOMElement) -> [(Double,Double)] { ranges(15,e) }
  public static func seekable(_ e: BrowserDOMElement) -> [(Double,Double)] { ranges(16,e) }
  private static func ranges(_ action: UInt32, _ e: BrowserDOMElement) -> [(Double,Double)] { guard var r = try? result(action, element:e) else { return [] }; guard let n = Int(exactly: r.u32()), n <= 65_536 else { return [] }; var a:[(Double,Double)]=[]; a.reserveCapacity(n); for _ in 0..<n { a.append((r.f64(),r.f64())) }; return a }
  public static func requestFullscreen(_ e: BrowserDOMElement) { _ = try? result(17, element:e) }
  public static func exitFullscreen(_ e: BrowserDOMElement) { _ = try? result(18, element:e) }
  public static func supportsPictureInPicture(_ e: BrowserDOMElement) -> Bool { guard var r = try? result(19, element:e) else { return false }; return r.u32() != 0 }
  public static func setPictureInPicture(_ enabled: Bool, _ e: BrowserDOMElement) { _ = try? result(20, element:e, flag:enabled) }
  public static func attachAdaptive(_ source: String, _ e: BrowserDOMElement) { _ = try? result(21, element:e, text:source) }
  public static func detachAdaptive(_ e: BrowserDOMElement) { _ = try? result(22, element:e) }
  @discardableResult public static func observe(_ e: BrowserDOMElement, event: String, _ receive: @escaping () -> Void) -> BrowserIOOperation {
    var out=IOWriter(); out.u32(e.identifier); out.text(event)
    return IORuntime.send(_BrowserIOProtocol.media, out) { status,_ in if status == 100 { receive() } }
  }
  @discardableResult public static func observeKeydown(_ e: BrowserDOMElement, _ receive: @escaping (String,Bool) -> Void) -> BrowserIOOperation {
    var out=IOWriter(); out.u32(e.identifier); out.text("__keydown")
    return IORuntime.send(_BrowserIOProtocol.media, out) { status,bytes in guard status == 100 else { return }; var r=IOReader(bytes:bytes); let key=r.text(); let repeated=r.u32() != 0; if r.finish() == nil { receive(key,repeated) } }
  }
}

/// IndexedDB key/value records. Values remain bytes; generic Codable is not implied.
public struct BrowserIndexedDB: Sendable {
  public let databaseName: String
  /// IndexedDB schema version. Increasing it lets the browser perform a
  /// native `onupgradeneeded` transition instead of treating every reload as
  /// a fresh in-memory store.
  public let version: Int
  public init(databaseName: String = "swiftuiweb", version: Int = 1) {
    precondition(!databaseName.isEmpty && version >= 1 && version <= 2_147_483_647)
    self.databaseName = databaseName
    self.version = version
  }
  private func command(_ action: UInt32, key: String = "", value: [UInt8] = []) -> IOWriter {
    var out = IOWriter(); out.text(databaseName); out.u32(action); out.text(key); out.data(value); out.u32(UInt32(version)); return out
  }
  @discardableResult
  public func get(_ key: String, completion: @escaping (Result<[UInt8]?, BrowserIOError>) -> Void) -> BrowserIOOperation {
    IORuntime.send(_BrowserIOProtocol.indexedDB, command(0, key: key)) { status, bytes in
      if status < 0 { completion(.failure(IORuntime.error(status, bytes))); return }
      var input = IOReader(bytes: bytes); let present = input.u32(); let value: [UInt8]? = present == 0 ? nil : input.data()
      if let error = input.finish() { completion(.failure(error)) } else { completion(.success(value)) }
    }
  }

  public func get(_ key: String) async throws -> [UInt8]? {
    let box = _BrowserIOOperationBox()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8]?, Error>) in
        box.operation = get(key) { result in continuation.resume(with: result) }
      }
    }, onCancel: { box.cancel() })
  }
  @discardableResult
  public func put(_ value: [UInt8], forKey key: String, completion: @escaping (Result<Void, BrowserIOError>) -> Void) -> BrowserIOOperation {
    mutate(command(1, key: key, value: value), completion)
  }
  public func put(_ value: [UInt8], forKey key: String) async throws {
    try await mutate(command(1, key: key, value: value))
  }
  @discardableResult
  public func remove(_ key: String, completion: @escaping (Result<Void, BrowserIOError>) -> Void) -> BrowserIOOperation { mutate(command(2, key: key), completion) }
  public func remove(_ key: String) async throws { try await mutate(command(2, key: key)) }
  @discardableResult
  public func removeAll(completion: @escaping (Result<Void, BrowserIOError>) -> Void) -> BrowserIOOperation { mutate(command(3), completion) }
  public func removeAll() async throws { try await mutate(command(3)) }
  @discardableResult
  public func keys(completion: @escaping (Result<[String], BrowserIOError>) -> Void) -> BrowserIOOperation {
    IORuntime.send(_BrowserIOProtocol.indexedDB, command(4)) { status, bytes in
      if status < 0 { completion(.failure(IORuntime.error(status, bytes))); return }
      var input = IOReader(bytes: bytes); let count = Int(exactly: input.u32()) ?? Int.max
      guard input.error == nil, count <= 100000 else { completion(.failure(input.error ?? BrowserIOError(code: -8, message: "Invalid IndexedDB key count"))); return }
      var keys: [String] = []; for _ in 0..<count { keys.append(input.text()) }
      if let error = input.finish() { completion(.failure(error)) } else { completion(.success(keys)) }
    }
  }
  public func keys() async throws -> [String] {
    let box = _BrowserIOOperationBox()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
        box.operation = keys { result in continuation.resume(with: result) }
      }
    }, onCancel: { box.cancel() })
  }

  public enum Mutation: Sendable, Equatable {
    case put(key: String, value: [UInt8])
    case remove(key: String)
    case removeAll
  }

  /// Commits a group of mutations in one native IndexedDB read-write
  /// transaction. If any operation fails, IndexedDB rolls the whole group
  /// back; the caller never observes a partially committed batch.
  public func transaction(_ mutations: [Mutation]) async throws {
    guard mutations.count <= 100_000 else {
      throw BrowserIOError(code: -1, message: "Too many IndexedDB transaction mutations")
    }
    var writer = IOWriter()
    writer.text(databaseName)
    writer.u32(UInt32(version))
    writer.u32(UInt32(mutations.count))
    for mutation in mutations {
      switch mutation {
      case .put(let key, let value): writer.u32(1); writer.text(key); writer.data(value)
      case .remove(let key): writer.u32(2); writer.text(key); writer.data([])
      case .removeAll: writer.u32(3); writer.text(""); writer.data([])
      }
    }
    let box = _BrowserIOOperationBox()
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        box.operation = IORuntime.send(_BrowserIOProtocol.indexedDBTransaction, writer) { status, bytes in
          if status < 0 { continuation.resume(throwing: IORuntime.error(status, bytes)) }
          else if !bytes.isEmpty { continuation.resume(throwing: BrowserIOError(code: -8, message: "Unexpected IndexedDB transaction result")) }
          else { continuation.resume() }
        }
      }
    }, onCancel: { box.cancel() })
  }
  private func mutate(_ command: IOWriter, _ completion: @escaping (Result<Void, BrowserIOError>) -> Void) -> BrowserIOOperation {
    IORuntime.send(_BrowserIOProtocol.indexedDB, command) { status, bytes in
      if status < 0 { completion(.failure(IORuntime.error(status, bytes))) }
      else if !bytes.isEmpty { completion(.failure(BrowserIOError(code: -8, message: "Unexpected IndexedDB write result"))) }
      else { completion(.success(())) }
    }
  }

  private func mutate(_ command: IOWriter) async throws {
    let box = _BrowserIOOperationBox()
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        box.operation = IORuntime.send(_BrowserIOProtocol.indexedDB, command) { status, bytes in
          if status < 0 { continuation.resume(throwing: IORuntime.error(status, bytes)) }
          else if !bytes.isEmpty { continuation.resume(throwing: BrowserIOError(code: -8, message: "Unexpected IndexedDB write result")) }
          else { continuation.resume() }
        }
      }
    }, onCancel: { box.cancel() })
  }
}
