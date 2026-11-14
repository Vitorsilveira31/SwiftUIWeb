// Foundation-shaped networking, the same on every host.
//
// The public surface mirrors the URLSession/URLRequest API SwiftUI applications use. The transport is the host's:
// SwiftUIWebBrowser installs a fetch-backed one at the platform boundary, and tests install their own.

@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

// Native URL/Data/JSON aliases live in NativeNetworkAdapter.swift. Keeping the
// declarations there means this façade source (and every Embedded build) has
// no Foundation import or Foundation-only implementation branch.
// Re-exporting the declaration (not aliasing it) keeps `URL` one type for clients that also see SwiftUIWebCore:
// a second typealias made `[URL].self` and `[URL]()` resolve as arrays of metatypes.
@_exported import struct SwiftUIWebTransferable.URL


/// The task a request's upload progress is reported against: the caller's task, or a detached one for a plain data call.
func _progressTask(_ task: URLSessionTask?, for request: URLRequest) -> URLSessionTask {
  if let task { return task }
  return URLSessionDataTask(request: request) { _ in }
}

/// The result of a task group whose first child has finished; a group with no child result was cancelled.
func _requireGroupResult<T>(_ result: T?) throws -> T {
  guard let result else { throw NetworkError.cancelled }
  return result
}

/// The file a download reports: the materialized file when the host made one, else the response URL.
func _downloadLocation(materialized: URL?, responseURL: URL?) throws -> URL {
  if let materialized { return materialized }
  if let responseURL { return responseURL }
  throw NetworkError.transport("The download response has no URL")
}

@inline(__always)
private func _networkURL(_ string: String) -> URL {
  return URL(string: string) ?? URL(string)
}

/// Host-side failure vocabulary. Hosts throw these from the transports they
/// install with `NetworkRuntime`; the public URLSession API converts them to
/// ``URLError`` (see `_urlErrorCode(_:)`).
package enum NetworkError: Error, Equatable, Sendable, CustomStringConvertible {
  case unavailable
  case invalidRequest(String)
  case badURL(String)
  case forbiddenHeader(String)
  case unsupported(String)
  case webSocketClosed(code: Int, reason: String?)
  case transport(String)
  case cancelled
  case timedOut
  /// The browser could not connect to the host (DNS, TCP, TLS or CORS failure before a response).
  case connectionFailed(String)
  /// The device is offline when the request fails.
  case offline(String)
  /// The connection failed while the response body was being received.
  case connectionLost(String)
  /// The response body exceeded the host's size limit.
  case responseTooLarge(String)
  /// The browser refused the request for a security reason (for example mixed content).
  case insecureRequest(String)

  package var description: String {
    switch self {
    case .unavailable: return "Networking is not available on this host"
    case .invalidRequest(let message): return message
    case .badURL(let message): return message
    case .forbiddenHeader(let field): return "The browser forbids the HTTP header '\(field)'"
    case .unsupported(let message): return message
    case .webSocketClosed(let code, let reason):
      return reason.map { "WebSocket closed (\(code)): \($0)" } ?? "WebSocket closed (\(code))"
    case .transport(let message): return message
    case .cancelled: return "The network request was cancelled"
    case .timedOut: return "The network request timed out"
    case .connectionFailed(let message): return message
    case .offline(let message): return message
    case .connectionLost(let message): return message
    case .responseTooLarge(let message): return message
    case .insecureRequest(let message): return message
    }
  }
}

/// HTTP methods understood by browsers. Custom token methods remain available
/// through `URLRequest.httpMethod`; this value is a convenience for common
/// requests and avoids stringly-typed call sites.
package enum HTTPMethod: String, CaseIterable, Sendable {
  case get = "GET"
  case head = "HEAD"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
  case options = "OPTIONS"
  case trace = "TRACE"
  case connect = "CONNECT"
  case track = "TRACK"
}

@inline(__always)
private func _networkHeaderEquals(_ lhs: String, _ rhs: String) -> Bool {
  // HTTP field names are ASCII case-insensitive. Avoid Foundation's
  // caseInsensitiveCompare, which is unavailable in Embedded Swift.
  guard lhs.utf8.count == rhs.utf8.count else { return false }
  return zip(lhs.utf8, rhs.utf8).allSatisfy { a, b in
    let la = (a >= 65 && a <= 90) ? a + 32 : a
    let lb = (b >= 65 && b <= 90) ? b + 32 : b
    return la == lb
  }
}

package enum URLSessionRedirectPolicy: String, Sendable, Hashable {
  /// Browser `fetch` follows redirects and exposes the final response URL.
  case follow
  /// Ask the browser for a manual redirect response where supported. Some
  /// cross-origin redirects are intentionally represented as opaque responses.
  case manual
  /// Reject redirects at the browser boundary.
  case error
}

package enum URLSessionCredentialsPolicy: String, Sendable, Hashable {
  /// Do not send cookies or HTTP authentication credentials.
  case omit
  /// Send credentials only to the request's origin.
  case sameOrigin
  /// Send credentials when the server's CORS policy permits it.
  case include
}

public struct URLRequest: Hashable, Sendable {
  /// Foundation's `URLRequest.CachePolicy` (`NSURLRequest.CachePolicy`), with Foundation's raw values.
  public enum CachePolicy: UInt, Sendable, Hashable {
    case useProtocolCachePolicy = 0
    case reloadIgnoringLocalCacheData = 1
    case reloadIgnoringLocalAndRemoteCacheData = 4
    case returnCacheDataElseLoad = 2
    case returnCacheDataDontLoad = 3
    case reloadRevalidatingCacheData = 5

    /// Foundation's deprecated spelling of `reloadIgnoringLocalCacheData`.
    public static var reloadIgnoringCacheData: CachePolicy { .reloadIgnoringLocalCacheData }
  }

  public var url: URL?
  public var httpMethod: String?
  public var allHTTPHeaderFields: [String: String]?
  public var httpBody: Data?
  /// Matches Foundation's per-request timeout override. A value of zero
  /// means that the URLSession configuration supplies the timeout.
  public var timeoutInterval: TimeInterval
  public var cachePolicy: CachePolicy
  public var mainDocumentURL: URL?
  /// Subprotocols requested by `URLSession.webSocketTask(with:protocols:)`.
  /// Browsers require these to be passed to the WebSocket constructor; they
  /// must not be forged as a `Sec-WebSocket-Protocol` request header.
  package var webSocketProtocols: [String]?
  /// A browser-only credentials mode for this request. `nil` uses the session's policy.
  /// Set through `SwiftUIWebWeb`'s `URLRequest.webCredentialsPolicy`.
  package var credentialsPolicyOverride: URLSessionCredentialsPolicy? = nil
  /// The browser HTTP cache mode (the `fetch` `cache` option's raw value) for this request's cache policy. Foundation's
  /// reload policies bypass the cache, and the revalidating one must not be answered from it either. The BrowserIO
  /// request type is not visible from this target, so the transport converts the raw value.
  package var browserCacheMode: String {
    switch cachePolicy {
    case .reloadIgnoringLocalCacheData, .reloadIgnoringLocalAndRemoteCacheData: return "no-store"
    case .reloadRevalidatingCacheData: return "no-cache"
    case .useProtocolCachePolicy, .returnCacheDataElseLoad, .returnCacheDataDontLoad: return "default"
    }
  }
  /// Foundation's per-request cookie switch. `false` sends this request with the browser's
  /// `credentials: "omit"`: no cookies go out and none from the response are stored. The browser
  /// cannot omit cookies alone, so HTTP authentication credentials are omitted too.
  public var httpShouldHandleCookies: Bool

  public init(url: URL, cachePolicy: CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60.0) {
    self.url = url
    httpMethod = nil
    allHTTPHeaderFields = nil
    httpBody = nil
    self.timeoutInterval = timeoutInterval
    self.cachePolicy = cachePolicy
    mainDocumentURL = nil
    webSocketProtocols = nil
    httpShouldHandleCookies = true
  }

  /// The timeout this request sets for itself. Foundation's default (60 seconds) leaves the session's
  /// `timeoutIntervalForRequest` in charge, as does zero.
  package var explicitTimeout: TimeInterval? { timeoutInterval > 0 && timeoutInterval != 60 ? timeoutInterval : nil }

  package var method: HTTPMethod? {
    get { httpMethod.flatMap { HTTPMethod(rawValue: $0.uppercased()) } }
    set { httpMethod = newValue?.rawValue }
  }

  package var effectiveHTTPMethod: String { (httpMethod ?? HTTPMethod.get.rawValue).uppercased() }

  public mutating func setValue(_ value: String?, forHTTPHeaderField field: String) {
    if allHTTPHeaderFields == nil { allHTTPHeaderFields = [:] }
    let existingKey = allHTTPHeaderFields?.keys.first {
      _networkHeaderEquals($0, field)
    }
    if let existingKey, existingKey != field {
      allHTTPHeaderFields?.removeValue(forKey: existingKey)
    }
    if let value {
      allHTTPHeaderFields?[field] = value
    } else {
      allHTTPHeaderFields?.removeValue(forKey: existingKey ?? field)
    }
  }

  public mutating func addValue(_ value: String, forHTTPHeaderField field: String) {
    if let old = self.value(forHTTPHeaderField: field), !old.isEmpty {
      setValue(old + ", " + value, forHTTPHeaderField: field)
    } else {
      setValue(value, forHTTPHeaderField: field)
    }
  }

  /// Adds an HTTP Basic credential when the server and CORS policy permit the
  /// `Authorization` header. Browsers do not expose native TLS challenge
  /// delegates, so explicit request credentials are the portable alternative.
  package mutating func setBasicAuthentication(user: String, password: String) {
    let credentials = Data(Array(user.utf8) + [0x3a] + Array(password.utf8)).base64EncodedString()
    setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
  }

  public func value(forHTTPHeaderField field: String) -> String? {
    guard let fields = allHTTPHeaderFields else { return nil }
    if let exact = fields[field] { return exact }
    let normalized = field.lowercased()
    return fields.first { $0.key.lowercased() == normalized }?.value
  }

  /// Performs checks that are meaningful before handing a request to browser
  /// `fetch`. It intentionally does not validate URL syntax because the
  /// Foundation-free URL value is an opaque host-provided string.
  package func validateForBrowser() throws {
    guard timeoutInterval.isFinite, timeoutInterval >= 0 else {
      throw NetworkError.invalidRequest("Request timeout interval must be finite and non-negative")
    }
    let method = effectiveHTTPMethod
    guard isHTTPToken(method) else {
      throw NetworkError.invalidRequest("HTTP method is not a valid token")
    }
    if httpBody != nil, method == HTTPMethod.get.rawValue || method == HTTPMethod.head.rawValue {
      throw NetworkError.invalidRequest("HTTP \(method) requests cannot contain a body")
    }
    if method == "CONNECT" || method == "TRACE" || method == "TRACK" {
      throw NetworkError.unsupported("The browser fetch API does not permit HTTP \(method) requests")
    }
    if let fields = allHTTPHeaderFields {
      for name in fields.keys {
        let lowercased = name.lowercased()
        if Self.browserForbiddenHeaderNames.contains(lowercased)
          || lowercased.hasPrefix("proxy-") || lowercased.hasPrefix("sec-") {
          throw NetworkError.forbiddenHeader(name)
        }
      }
    }
    if let protocols = webSocketProtocols {
      guard Set(protocols).count == protocols.count,
            protocols.allSatisfy({ isHTTPToken($0) }) else {
        throw NetworkError.invalidRequest("WebSocket subprotocols must be valid HTTP tokens")
      }
    }
  }

  private static let browserForbiddenHeaderNames: Set<String> = [
    "accept-charset", "accept-encoding", "access-control-request-headers",
    "access-control-request-method", "connection", "content-length", "cookie",
    "cookie2", "date", "dnt", "expect", "host", "keep-alive", "origin",
    "referer", "te", "trailer", "transfer-encoding", "upgrade", "via",
    "proxy-", "sec-"
  ]
}

/// RFC 9110 `token`: one or more `tchar` characters, which are ASCII letters,
/// digits and `!#$%&'*+-.^_`|~`.
func isHTTPToken(_ value: String) -> Bool {
  !value.utf8.isEmpty && value.utf8.allSatisfy { byte in
    (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
      || "!#$%&'*+-.^_`|~".utf8.contains(byte)
  }
}

open class URLResponse: @unchecked Sendable {
  public let url: URL?
  public let expectedContentLength: Int64
  public let mimeType: String?
  public let textEncodingName: String?
  package let httpVersion: String?

  public init(url: URL, mimeType: String?, expectedContentLength: Int, textEncodingName: String?) {
    self.url = url
    self.expectedContentLength = Int64(expectedContentLength)
    self.mimeType = mimeType
    self.textEncodingName = textEncodingName
    httpVersion = nil
  }

  package init(
    url: URL,
    expectedContentLength: Int64 = -1,
    mimeType: String? = nil,
    textEncodingName: String? = nil,
    httpVersion: String? = nil
  ) {
    self.url = url
    self.expectedContentLength = expectedContentLength
    self.mimeType = mimeType
    self.textEncodingName = textEncodingName
    self.httpVersion = httpVersion
  }
}

public final class HTTPURLResponse: URLResponse, @unchecked Sendable {
  public let statusCode: Int
  public let allHeaderFields: [String: String]

  package var isInformational: Bool { (100..<200).contains(statusCode) }
  package var isSuccess: Bool { (200..<300).contains(statusCode) }
  package var isRedirection: Bool { (300..<400).contains(statusCode) }
  package var isClientError: Bool { (400..<500).contains(statusCode) }
  package var isServerError: Bool { (500..<600).contains(statusCode) }

  package init(
    url: URL,
    statusCode: Int,
    headerFields: [String: String] = [:],
    expectedContentLength: Int64 = -1,
    mimeType: String? = nil,
    textEncodingName: String? = nil,
    httpVersion: String? = nil
  ) {
    self.statusCode = statusCode
    allHeaderFields = headerFields
    super.init(
      url: url,
      expectedContentLength: expectedContentLength,
      mimeType: mimeType,
      textEncodingName: textEncodingName,
      httpVersion: httpVersion
    )
  }

  public convenience init?(
    url: URL,
    statusCode: Int,
    httpVersion: String? = nil,
    headerFields: [String: String]? = nil
  ) {
    self.init(url: url, statusCode: statusCode, headerFields: headerFields ?? [:], httpVersion: httpVersion)
  }

  public func value(forHTTPHeaderField field: String) -> String? {
    if let exact = allHeaderFields[field] { return exact }
    let normalized = field.lowercased()
    return allHeaderFields.first { $0.key.lowercased() == normalized }?.value
  }
}

public struct URLSessionConfiguration: Sendable {
  public var timeoutIntervalForRequest: Double
  public var timeoutIntervalForResource: Double
  public var allowsCellularAccess: Bool
  public var allowsExpensiveNetworkAccess: Bool
  public var allowsConstrainedNetworkAccess: Bool
  public var waitsForConnectivity: Bool
  public var httpAdditionalHeaders: [String: String]?
  public var requestCachePolicy: URLRequest.CachePolicy
  package var redirectPolicy: URLSessionRedirectPolicy
  package var credentialsPolicy: URLSessionCredentialsPolicy
  public var httpShouldSetCookies: Bool
  public var httpCookieAcceptPolicy: HTTPCookie.AcceptPolicy
  /// Apple's `httpCookieStorage`. The browser keeps the cookies; this storage is the page's view of them.
  public var httpCookieStorage: HTTPCookieStorage?
  /// Protocol classes consulted before the browser transport, in order (Apple's `URLProtocol` seam).
  public var protocolClasses: [AnyClass]?

  /// Foundation's default configuration. The browser defaults are bounded: unlike Foundation's native
  /// transport, a blocked/CORS-rejected fetch may otherwise stay pending indefinitely.
  public init() {
    self.init(timeoutIntervalForRequest: 15)
  }

  package init(
    timeoutIntervalForRequest: Double = 15,
    timeoutIntervalForResource: Double = 604_800,
    allowsCellularAccess: Bool = true,
    allowsExpensiveNetworkAccess: Bool = true,
    allowsConstrainedNetworkAccess: Bool = true,
    waitsForConnectivity: Bool = false,
    httpAdditionalHeaders: [String: String]? = nil,
    requestCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
    redirectPolicy: URLSessionRedirectPolicy = .follow,
    credentialsPolicy: URLSessionCredentialsPolicy = .sameOrigin,
    httpShouldSetCookies: Bool = true,
    httpCookieAcceptPolicy: HTTPCookie.AcceptPolicy = .onlyFromMainDocumentDomain,
    httpCookieStorage: HTTPCookieStorage? = HTTPCookieStorage.shared
  ) {
    self.timeoutIntervalForRequest = timeoutIntervalForRequest
    self.timeoutIntervalForResource = timeoutIntervalForResource
    self.allowsCellularAccess = allowsCellularAccess
    self.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
    self.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
    self.waitsForConnectivity = waitsForConnectivity
    self.httpAdditionalHeaders = httpAdditionalHeaders
    self.requestCachePolicy = requestCachePolicy
    self.redirectPolicy = redirectPolicy
    self.credentialsPolicy = credentialsPolicy
    self.httpShouldSetCookies = httpShouldSetCookies
    self.httpCookieAcceptPolicy = httpCookieAcceptPolicy
    self.httpCookieStorage = httpCookieStorage
  }

  /// The browser `credentials` mode for `request`: the configuration's policy, unless this session
  /// (`httpShouldSetCookies`) or the request (`httpShouldHandleCookies`) turned cookies off. The
  /// browser's cookie jar does the rest; cookies never reach Swift.
  package func credentialsPolicy(for request: URLRequest) -> URLSessionCredentialsPolicy {
    guard httpShouldSetCookies && request.httpShouldHandleCookies else { return .omit }
    return request.credentialsPolicyOverride ?? credentialsPolicy
  }

  public static var `default`: URLSessionConfiguration { URLSessionConfiguration() }
  public static var ephemeral: URLSessionConfiguration { URLSessionConfiguration() }

  package func validateForBrowser() throws {
    guard timeoutIntervalForRequest.isFinite, timeoutIntervalForRequest >= 0,
          timeoutIntervalForResource.isFinite, timeoutIntervalForResource >= 0 else {
      throw NetworkError.invalidRequest("Session timeout intervals must be finite and non-negative")
    }
    if let headers = httpAdditionalHeaders {
      var request = URLRequest(url: _networkURL("about:blank"))
      request.allHTTPHeaderFields = headers
      try request.validateForBrowser()
    }
  }
}

public struct URLCredential: Hashable, Sendable {
  public let user: String?
  public let password: String?
  public let persistence: Persistence

  public var hasPassword: Bool { password != nil }

  public enum Persistence: UInt, Sendable, Hashable { case none = 0, forSession = 1, permanent = 2, synchronizable = 3 }

  public init(user: String, password: String, persistence: Persistence = .none) {
    self.user = user
    self.password = password
    self.persistence = persistence
  }
}

package enum NetworkConnectivity: String, Sendable, Hashable {
  case unknown
  case online
  case offline
}

/// An `NWPath.Status`-shaped value for the browser's limited signal. Browser
/// adapters emit `.satisfied`, `.unsatisfied`, or `.unknown`; they never emit
/// `.requiresConnection` because the Web platform cannot expose that native
/// path state. `.satisfied` means that the browser currently reports an online
/// network interface; it is not a probe of Internet or server reachability.
package enum NetworkPathStatus: String, Sendable, Hashable {
  case satisfied
  case unsatisfied
  case requiresConnection
  case unknown
}

/// A browser connectivity snapshot. The status reflects the user agent's
/// `navigator.onLine` heuristic, not an end-to-end reachability probe.
package struct NetworkConnectivityState: Sendable, Equatable {
  package let status: NetworkConnectivity
  package let effectiveType: String?
  package let downlinkMbps: Double?
  package let rttMilliseconds: Int?
  /// Browser APIs do not expose the interface-cost semantics of `NWPath`.
  /// These remain `nil` rather than being guessed from `effectiveType`.
  package let isExpensive: Bool?
  package let isConstrained: Bool?

  package init(
    status: NetworkConnectivity,
    effectiveType: String? = nil,
    downlinkMbps: Double? = nil,
    rttMilliseconds: Int? = nil,
    isExpensive: Bool? = nil,
    isConstrained: Bool? = nil
  ) {
    self.status = status
    self.effectiveType = effectiveType
    self.downlinkMbps = downlinkMbps
    self.rttMilliseconds = rttMilliseconds
    self.isExpensive = isExpensive
    self.isConstrained = isConstrained
  }

  /// `NWPath.Status`-shaped status for callers that only need path
  /// satisfaction semantics. The browser's online bit is intentionally not
  /// presented as a reachability check.
  package var pathStatus: NetworkPathStatus {
    switch status {
    case .online: return .satisfied
    case .offline: return .unsatisfied
    case .unknown: return .unknown
    }
  }

  package var isOnline: Bool? {
    switch status {
    case .online: return true
    case .offline: return false
    case .unknown: return nil
    }
  }
}

/// Whether a connectivity monitor still exists, for host callbacks that can arrive after it is gone. Embedded Swift has no
/// weak references, so the callbacks hold this box and the monitor unowned (as `_CLManagerLiveness` does).
final class _NetworkMonitorLiveness: @unchecked Sendable {
  var alive = true
}

/// An event-driven browser equivalent of the useful part of `NWPathMonitor`.
/// Set `pathUpdateHandler` and call `start()` for callback-style updates, or
/// consume `updates` with Swift concurrency. The monitor owns its browser
/// subscription and releases it when cancelled, when its stream terminates,
/// or when it is deallocated.
package final class NetworkConnectivityMonitor: @unchecked Sendable {
  package typealias PathUpdateHandler = @Sendable (NetworkConnectivityState) -> Void

  package var pathUpdateHandler: PathUpdateHandler? {
    didSet {
      guard started, let pathUpdateHandler else { return }
      pathUpdateHandler(currentPath)
    }
  }

  /// Alias for clients that prefer the existing connectivity terminology.
  package var updateHandler: PathUpdateHandler? {
    get { pathUpdateHandler }
    set { pathUpdateHandler = newValue }
  }

  package private(set) var currentPath: NetworkConnectivityState
  package var currentState: NetworkConnectivityState { currentPath }

  private var started = false
  private var subscriptionCancellation: (@Sendable () -> Void)?
  private var subscriptionLiveness: _NetworkMonitorLiveness?
  private var streamContinuations: [UInt64: AsyncStream<NetworkConnectivityState>.Continuation] = [:]
  private var nextStreamID: UInt64 = 0

  package init() {
    currentPath = NetworkRuntime.connectivity
  }

  /// Begins listening for browser online/offline transitions and optional
  /// Network Information changes. Calling start more than once is idempotent,
  /// matching `NWPathMonitor` lifecycle usage.
  package func start() {
    guard !started else { return }
    started = true
    currentPath = NetworkRuntime.connectivity
    // The host callback holds the liveness box and the monitor unowned, never the monitor itself, so deinit runs and
    // unsubscribes; the callback checks the box before it touches the monitor.
    let liveness = _NetworkMonitorLiveness()
    subscriptionLiveness = liveness
    subscriptionCancellation = NetworkRuntime.subscribeConnectivity { [unowned(unsafe) self, liveness] state in
      guard liveness.alive else { return }
      self.receive(state)
    }
    // NWPathMonitor delivers an initial path after starting. Do the same even
    // when the host has no event subscription and only supplies a snapshot.
    pathUpdateHandler?(currentPath)
  }

  /// Stops listening, finishes all async streams, and releases the host's
  /// browser event listeners. A later `start()` creates a fresh subscription.
  package func cancel() {
    guard started || subscriptionCancellation != nil || !streamContinuations.isEmpty else { return }
    started = false
    subscriptionLiveness?.alive = false
    subscriptionLiveness = nil
    subscriptionCancellation?()
    subscriptionCancellation = nil
    let continuations = Array(streamContinuations.values)
    streamContinuations.removeAll(keepingCapacity: false)
    for continuation in continuations { continuation.finish() }
  }

  /// Returns a cold async stream. The current snapshot is yielded first;
  /// subsequent values are produced only when the browser state or its
  /// available Network Information metadata changes.
  package func connectivityUpdates() -> AsyncStream<NetworkConnectivityState> {
    let id = nextStreamID
    nextStreamID &+= 1
    return AsyncStream { [self] continuation in
      continuation.onTermination = { [self] _ in
        removeStream(id: id)
      }
      self.start()
      self.streamContinuations[id] = continuation
      continuation.yield(self.currentPath)
    }
  }

  package var updates: AsyncStream<NetworkConnectivityState> { connectivityUpdates() }

  private func receive(_ state: NetworkConnectivityState) {
    guard state != currentPath else { return }
    currentPath = state
    pathUpdateHandler?(state)
    for continuation in Array(streamContinuations.values) {
      continuation.yield(state)
    }
  }

  private func removeStream(id: UInt64) {
    streamContinuations.removeValue(forKey: id)
    if streamContinuations.isEmpty, pathUpdateHandler == nil {
      cancel()
    }
  }

  deinit { cancel() }
}

/// Short spelling for code ported from Apple's `NWPathMonitor` API. Browser
/// callers should use `currentPath.pathStatus` rather than assuming that an
/// online bit proves Internet reachability.
package typealias NetworkPathMonitor = NetworkConnectivityMonitor

package enum WebSocketConnectionState: String, Sendable, Hashable {
  case connecting
  case open
  case closing
  case closed
}

package struct WebSocketCloseInfo: Sendable, Equatable {
  package let code: Int
  package let reason: Data?
  package let wasClean: Bool

  package init(code: Int, reason: Data? = nil, wasClean: Bool = false) {
    self.code = code
    self.reason = reason
    self.wasClean = wasClean
  }

  package var reasonString: String? { reason?.utf8String() }
}

/// A browser-neutral WebSocket connection. JavaScript interop implementations stay
/// in `SwiftUIWebBrowser`; applications only see Foundation-shaped messages.
package struct WebSocketConnection: Sendable {
  package typealias Send = @Sendable (URLSessionWebSocketTask.Message) async throws -> Void
  package typealias Receive = @Sendable () async throws -> URLSessionWebSocketTask.Message
  package typealias Ping = @Sendable () async throws -> Void
  package typealias Close = @Sendable (_ code: Int, _ reason: Data?) -> Void
  package typealias State = @Sendable () -> WebSocketConnectionState
  package typealias CloseInfo = @Sendable () -> WebSocketCloseInfo?

  fileprivate let sendOperation: Send
  fileprivate let receiveOperation: Receive
  fileprivate let pingOperation: Ping?
  fileprivate let closeOperation: Close
  fileprivate let stateOperation: State
  fileprivate let closeInfoOperation: CloseInfo
  package let negotiatedProtocol: String?

  package init(
    send: @escaping Send,
    receive: @escaping Receive,
    close: @escaping Close,
    ping: Ping? = nil,
    state: State? = nil,
    closeInfo: CloseInfo? = nil,
    negotiatedProtocol: String? = nil
  ) {
    sendOperation = send
    receiveOperation = receive
    pingOperation = ping
    closeOperation = close
    stateOperation = state ?? { .open }
    closeInfoOperation = closeInfo ?? { nil }
    self.negotiatedProtocol = negotiatedProtocol
  }
}

@inline(__always)
private func _networkCheckCancellation() throws {
#if hasFeature(Embedded)
  if Task.isCancelled { throw CancellationError() }
#else
  try Task.checkCancellation()
#endif
}

private func _networkSleep(nanoseconds: UInt64) async throws {
#if hasFeature(Embedded)
  // Embedded Swift does not expose Task.sleep. Browser hosts install the
  // timeout scheduler with setTimeout, keeping clock ownership outside Swift.
  let seconds = Double(nanoseconds) / 1_000_000_000.0
  let race = _NetworkSleepRace()
  try await withTaskCancellationHandler(operation: {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      race.setContinuation(continuation)
      guard let cancellation = NetworkRuntime._scheduleTimeout(seconds, {
        race.finish(.success(()))
      }) else {
        race.finish(.failure(NetworkError.unavailable))
        return
      }
      race.timeoutCancellation = cancellation
    }
  }, onCancel: {
    race.finish(.failure(CancellationError()))
  })
#else
  try await Task.sleep(nanoseconds: nanoseconds)
#endif
}

package enum NetworkRuntime {
  package typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
  package typealias ConfiguredTransport = @Sendable (URLRequest, URLSessionConfiguration) async throws -> (Data, HTTPURLResponse)
  package typealias StreamingTransport = @Sendable (URLRequest, URLSessionConfiguration) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
  package typealias DownloadMaterializer = @Sendable (Data, HTTPURLResponse) -> URL?
  package typealias ConnectivityProvider = @Sendable () -> NetworkConnectivityState
  package typealias ConnectivitySubscription = @Sendable (
    _ callback: @escaping @Sendable (NetworkConnectivityState) -> Void
  ) -> (@Sendable () -> Void)
  package typealias WebSocketTransport = @Sendable (URLRequest, URLSessionConfiguration) async throws -> WebSocketConnection
  /// The progress a buffered transfer reports while it runs. `upload` receives the cumulative bytes sent and the
  /// expected total; `download` the cumulative bytes received and the expected length (-1 when unknown). Either may
  /// be called several times before the response completes.
  package struct TransferProgress: Sendable {
    package var upload: (@Sendable (_ totalSent: Int64, _ totalExpected: Int64) -> Void)?
    package var download: (@Sendable (_ totalReceived: Int64, _ expected: Int64) -> Void)?

    package init(
      upload: (@Sendable (Int64, Int64) -> Void)? = nil,
      download: (@Sendable (Int64, Int64) -> Void)? = nil
    ) {
      self.upload = upload
      self.download = download
    }
  }
  /// A request/response transport that reports transfer progress as it runs (see `TransferProgress`).
  package typealias TransferProgressTransport = @Sendable (
    _ request: URLRequest,
    _ configuration: URLSessionConfiguration,
    _ progress: TransferProgress
  ) async throws -> (Data, HTTPURLResponse)
  /// Host-provided wall-clock scheduling used by runtimes whose async clock is
  /// not backed by the platform event loop (for example a browser fetch that
  /// is blocked by a CORS policy). The callback returns a cancellation token
  /// so completed requests do not leave timers behind.
  package typealias TimeoutScheduler = @Sendable (
    _ seconds: Double,
    _ callback: @escaping @Sendable () -> Void
  ) -> (@Sendable () -> Void)

  private struct HostHooks {
    var transport: Transport?
    var configuredTransport: ConfiguredTransport?
    var streamingTransport: StreamingTransport?
    var downloadMaterializer: DownloadMaterializer?
    var connectivityProvider: ConnectivityProvider?
    var connectivitySubscription: ConnectivitySubscription?
    var webSocketTransport: WebSocketTransport?
    var timeoutScheduler: TimeoutScheduler?
    var transferProgressTransport: TransferProgressTransport?
  }
  // Hosts install their hooks once; requests on any thread read them under the lock.
  private static let hooks = _Locked(HostHooks())
  private static var transport: Transport? {
    get { hooks.withLock { $0.transport } }
    set { hooks.withLock { $0.transport = newValue } }
  }
  private static var configuredTransport: ConfiguredTransport? {
    get { hooks.withLock { $0.configuredTransport } }
    set { hooks.withLock { $0.configuredTransport = newValue } }
  }
  private static var streamingTransport: StreamingTransport? {
    get { hooks.withLock { $0.streamingTransport } }
    set { hooks.withLock { $0.streamingTransport = newValue } }
  }
  private static var downloadMaterializer: DownloadMaterializer? {
    get { hooks.withLock { $0.downloadMaterializer } }
    set { hooks.withLock { $0.downloadMaterializer = newValue } }
  }
  private static var connectivityProvider: ConnectivityProvider? {
    get { hooks.withLock { $0.connectivityProvider } }
    set { hooks.withLock { $0.connectivityProvider = newValue } }
  }
  private static var connectivitySubscription: ConnectivitySubscription? {
    get { hooks.withLock { $0.connectivitySubscription } }
    set { hooks.withLock { $0.connectivitySubscription = newValue } }
  }
  private static var webSocketTransport: WebSocketTransport? {
    get { hooks.withLock { $0.webSocketTransport } }
    set { hooks.withLock { $0.webSocketTransport = newValue } }
  }
  private static var timeoutScheduler: TimeoutScheduler? {
    get { hooks.withLock { $0.timeoutScheduler } }
    set { hooks.withLock { $0.timeoutScheduler = newValue } }
  }
  private static var transferProgressTransport: TransferProgressTransport? {
    get { hooks.withLock { $0.transferProgressTransport } }
    set { hooks.withLock { $0.transferProgressTransport = newValue } }
  }

#if hasFeature(Embedded)
  fileprivate static func _scheduleTimeout(_ seconds: Double, _ callback: @escaping @Sendable () -> Void) -> (@Sendable () -> Void)? {
    timeoutScheduler?(seconds, callback)
  }
#endif

  /// Installs the host transport. SwiftUIWebBrowser calls this once with a browser `fetch` implementation; other
  /// hosts (tests, tools) install their own. Without one, requests fail as unavailable.
  package static func install(_ transport: Transport?) {
    self.transport = transport
  }

  /// Installs a transport that receives session configuration (redirect and
  /// credentials policy in particular). Installing this does not remove the
  /// legacy request-only transport, so existing hosts remain source-compatible.
  package static func installConfigured(_ transport: ConfiguredTransport?) {
    configuredTransport = transport
  }

  package static func installStreaming(_ transport: StreamingTransport?) {
    streamingTransport = transport
  }

  package static func installDownloadMaterializer(_ materializer: DownloadMaterializer?) {
    downloadMaterializer = materializer
  }

  package static func installConnectivityProvider(_ provider: ConnectivityProvider?) {
    connectivityProvider = provider
  }

  /// Installs an event source for connectivity transitions. The returned
  /// cancellation closure must remove all host listeners and release any host
  /// references. Browser adapters use `online`/`offline` and (when available)
  /// Network Information `change` events; they do not poll `navigator.onLine`.
  package static func installConnectivitySubscription(_ subscription: ConnectivitySubscription?) {
    connectivitySubscription = subscription
  }

  package static func installWebSocket(_ transport: WebSocketTransport?) {
    webSocketTransport = transport
  }

  /// Installs a transport that reports upload and download progress while a buffered request runs. Without one,
  /// a request still succeeds through the ordinary transports: its upload is reported once, when it completes, and
  /// its download only through the task's final counts.
  package static func installTransferProgress(_ transport: TransferProgressTransport?) {
    transferProgressTransport = transport
  }

  /// Installs an optional host clock. The standard implementation falls back
  /// to `Task.sleep`; browser hosts install this with `setTimeout` so a fetch
  /// that never settles still produces a deterministic timeout.
  package static func installTimeoutScheduler(_ scheduler: TimeoutScheduler?) {
    self.timeoutScheduler = scheduler
  }

  package static var isAvailable: Bool {
    transport != nil || configuredTransport != nil || streamingTransport != nil || webSocketTransport != nil
  }

  /// Whether a request/response transport (rather than only a streaming,
  /// WebSocket, or connectivity capability) has been installed. Native
  /// bootstrap uses this narrower check so an independently installed stream
  /// adapter cannot accidentally disable the default data transport.
  static var hasRequestTransport: Bool {
    transport != nil || configuredTransport != nil
  }

  static var hasTransferProgressTransport: Bool { transferProgressTransport != nil }

  static var hasStreamingTransport: Bool { streamingTransport != nil }

  package static var connectivity: NetworkConnectivityState {
    connectivityProvider?() ?? NetworkConnectivityState(status: .unknown)
  }

  fileprivate static func subscribeConnectivity(
    _ callback: @escaping @Sendable (NetworkConnectivityState) -> Void
  ) -> (@Sendable () -> Void) {
    if let connectivitySubscription {
      return connectivitySubscription(callback)
    }
    return {}
  }

  fileprivate static func perform(
    _ request: URLRequest,
    configuration: URLSessionConfiguration,
    progress: TransferProgress? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    try configuration.validateForBrowser()
    try request.validateForBrowser()
    do {
      let result: (Data, HTTPURLResponse)
      if let progress, let transferProgressTransport {
        result = try await transferProgressTransport(request, configuration, progress)
      } else if let configuredTransport {
        result = try await configuredTransport(request, configuration)
      } else if let transport {
        result = try await transport(request)
      } else {
        throw NetworkError.unavailable
      }
      try _networkCheckCancellation()
      return result
    } catch is CancellationError {
      throw NetworkError.cancelled
    }
  }

  fileprivate static func performStreaming(
    _ request: URLRequest,
    configuration: URLSessionConfiguration
  ) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
    try configuration.validateForBrowser()
    try request.validateForBrowser()
    do {
      if let streamingTransport {
        return try await streamingTransport(request, configuration)
      }
      let (data, response) = try await perform(request, configuration: configuration)
      let stream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(data)
        continuation.finish()
      }
      return (response, stream)
    } catch is CancellationError {
      throw NetworkError.cancelled
    }
  }

  fileprivate static func materializeDownload(_ data: Data, response: HTTPURLResponse) -> URL? {
    downloadMaterializer?(data, response)
  }

  fileprivate static func webSocket(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> WebSocketConnection {
    try configuration.validateForBrowser()
    try request.validateForBrowser()
    guard let webSocketTransport else { throw NetworkError.unsupported("WebSocket is not available on this host") }
    do {
      return try await webSocketTransport(request, configuration)
    } catch is CancellationError {
      throw NetworkError.cancelled
    }
  }

  fileprivate static func scheduleTimeout(
    _ seconds: Double,
    callback: @escaping @Sendable () -> Void
  ) -> (@Sendable () -> Void)? {
    timeoutScheduler?(seconds, callback)
  }
}

/// The at-most-once result of a request racing its transport, its timeout and
/// task cancellation. `finish` runs on whichever thread completes the
/// transport, fires the timeout or cancels the task, while `setContinuation`
/// runs on the request's own thread, so every member is read and written
/// under `lock`. An unsynchronized check-then-store let a cancellation that
/// landed between "no continuation yet" and "store the continuation" resume
/// nothing and leave the request suspended forever (an intermittent hang in
/// the native suite). Continuations and tasks are resumed and cancelled
/// outside the lock. In Embedded Swift the lock is a no-op.
private final class _NetworkRequestRace<ResultValue: Sendable>: @unchecked Sendable {

  private let lock = _RuntimeLock()
  private var finished = false
  private var continuation: CheckedContinuation<ResultValue, Error>?
  private var pendingResult: Result<ResultValue, Error>?
  private var transportTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var timeoutCancellation: (@Sendable () -> Void)?

  func setTransportTask(_ task: Task<Void, Never>) {
    let finished = lock.withLock { transportTask = task; return self.finished }
    if finished { task.cancel() }
  }

  func setTimeoutTask(_ task: Task<Void, Never>) {
    let finished = lock.withLock { timeoutTask = task; return self.finished }
    if finished { task.cancel() }
  }

  func setTimeoutCancellation(_ cancellation: @escaping @Sendable () -> Void) {
    let finished = lock.withLock { timeoutCancellation = cancellation; return self.finished }
    if finished { cancellation() }
  }

  func finish(_ result: Result<ResultValue, Error>) {
    let outcome = lock.withLock { () -> (CheckedContinuation<ResultValue, Error>?, Task<Void, Never>?, Task<Void, Never>?, (@Sendable () -> Void)?)? in
      guard !finished else { return nil }
      finished = true
      let continuation = self.continuation
      self.continuation = nil
      if continuation == nil { pendingResult = result }
      return (continuation, transportTask, timeoutTask, timeoutCancellation)
    }
    guard let (continuation, transportTask, timeoutTask, timeoutCancellation) = outcome else { return }
    continuation?.resume(with: result)
    transportTask?.cancel()
    timeoutTask?.cancel()
    timeoutCancellation?()
  }

  func setContinuation(_ continuation: CheckedContinuation<ResultValue, Error>) {
    let pending = lock.withLock { () -> Result<ResultValue, Error>? in
      if let pendingResult {
        self.pendingResult = nil
        return pendingResult
      }
      self.continuation = continuation
      return nil
    }
    if let pending { continuation.resume(with: pending) }
  }

  func cancel() {
    finish(.failure(NetworkError.cancelled))
  }
}

#if hasFeature(Embedded)
/// A one-shot host timer needs the same at-most-once and late-assignment
/// semantics as a network request. In particular, task cancellation can race
/// with installation of the browser timer token; storing a pending result
/// keeps both paths deterministic and prevents a leaked continuation.
private final class _NetworkSleepRace: @unchecked Sendable {
  private var finished = false
  private var pendingResult: Result<Void, Error>?
  private var continuation: CheckedContinuation<Void, Error>?
  var timeoutCancellation: (@Sendable () -> Void)? {
    didSet { if finished { timeoutCancellation?() } }
  }

  func setContinuation(_ continuation: CheckedContinuation<Void, Error>) {
    if let pendingResult {
      continuation.resume(with: pendingResult)
      self.pendingResult = nil
    } else {
      self.continuation = continuation
    }
  }

  func finish(_ result: Result<Void, Error>) {
    guard !finished else { return }
    finished = true
    if let continuation {
      continuation.resume(with: result)
      self.continuation = nil
    } else {
      pendingResult = result
    }
    timeoutCancellation?()
  }
}
#endif

/// The at-most-once termination of a streamed body racing its producer, its
/// timeout and the consumer's cancellation; synchronized like
/// `_NetworkRequestRace`.
private final class _NetworkStreamRace: @unchecked Sendable {
  private let lock = _RuntimeLock()
  private let failingURL: URL?
  private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
  private var bodyTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var timeoutCancellation: (@Sendable () -> Void)?
  private var finished = false

  init(failingURL: URL?) {
    self.failingURL = failingURL
  }

  func setContinuation(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
    lock.withLock { self.continuation = continuation }
  }

  func setBodyTask(_ task: Task<Void, Never>) {
    let finished = lock.withLock { bodyTask = task; return self.finished }
    if finished { task.cancel() }
  }

  func setTimeoutTask(_ task: Task<Void, Never>) {
    let finished = lock.withLock { timeoutTask = task; return self.finished }
    if finished { task.cancel() }
  }

  func setTimeoutCancellation(_ cancellation: @escaping @Sendable () -> Void) {
    let finished = lock.withLock { timeoutCancellation = cancellation; return self.finished }
    if finished { cancellation() }
  }

  func yield(_ data: Data) {
    lock.withLock { finished ? nil : continuation }?.yield(data)
  }

  func finish(_ error: Error? = nil) {
    let outcome = lock.withLock { () -> (AsyncThrowingStream<Data, Error>.Continuation?, Task<Void, Never>?, Task<Void, Never>?, (@Sendable () -> Void)?)? in
      guard !finished else { return nil }
      finished = true
      return (continuation, bodyTask, timeoutTask, timeoutCancellation)
    }
    guard let (continuation, bodyTask, timeoutTask, timeoutCancellation) = outcome else { return }
    if let error { continuation?.finish(throwing: _urlError(error, failingURL: failingURL)) }
    else { continuation?.finish() }
    bodyTask?.cancel()
    timeoutTask?.cancel()
    timeoutCancellation?()
  }

  func cancel() { finish(NetworkError.cancelled) }
  func timeOut() { finish(NetworkError.timedOut) }
}

/// Foundation's `Progress` for the Foundation-free runtimes, with the counters a transfer maintains. Native builds
/// use Foundation's class (see NativeNetworkAdapter.swift).
open class Progress: @unchecked Sendable {
  public var totalUnitCount: Int64
  /// The units this progress completed itself, not counting children.
  private var ownCompletedUnitCount: Int64 = 0
  private var children: [(child: Progress, pendingUnitCount: Int64)] = []

  public init(totalUnitCount: Int64) {
    self.totalUnitCount = totalUnitCount
  }

  /// The completed units: its own, plus the pending units of each child that has finished, as Foundation counts them.
  /// Setting it fixes the total read back, as in Foundation, where a finished child's units are already part of it.
  public var completedUnitCount: Int64 {
    get { ownCompletedUnitCount + finishedChildUnits }
    set { ownCompletedUnitCount = newValue - finishedChildUnits }
  }

  private var finishedChildUnits: Int64 {
    children.reduce(0) { total, entry in entry.child.isFinished ? total + entry.pendingUnitCount : total }
  }

  private var isFinished: Bool { totalUnitCount > 0 && completedUnitCount >= totalUnitCount }

  /// Adds a child whose fraction counts for `inUnitCount` of this progress's units, as Foundation does.
  public func addChild(_ child: Progress, withPendingUnitCount inUnitCount: Int64) {
    children.append((child, inUnitCount))
  }

  /// The completed share of the total, with each child's fraction counted for its pending units. 0 while the total
  /// is unknown (-1) or empty.
  public var fractionCompleted: Double {
    guard totalUnitCount > 0 else { return 0 }
    var completed = Double(ownCompletedUnitCount)
    for (child, pending) in children {
      completed += child.fractionCompleted * Double(pending)
    }
    return min(1, max(0, completed / Double(totalUnitCount)))
  }
}

open class URLSessionTask: @unchecked Sendable {
  public enum State: Int, Sendable, Hashable {
    case running = 0
    case suspended = 1
    case canceling = 2
    case completed = 3
  }

  private static let identifiers = _Locked(0)
  public let taskIdentifier: Int
  fileprivate let request: URLRequest
  public var originalRequest: URLRequest? { request }
  public var currentRequest: URLRequest? { request }
  public private(set) var response: URLResponse?
  public private(set) var state: State = .suspended
  public private(set) var countOfBytesSent: Int64 = 0
  public private(set) var countOfBytesReceived: Int64 = 0
  public private(set) var countOfBytesExpectedToSend: Int64 = 0
  public private(set) var countOfBytesExpectedToReceive: Int64 = -1
  /// Foundation's `progress` for the receive side of the transfer, as Foundation models it: 100 units, 5 of them
  /// done once the response arrives, the body's share (95 units) following the bytes received when the length is
  /// known, and all 100 when the task finishes. Upload bytes do not move it.
  public let progress = Progress(totalUnitCount: 100)
  /// The body's share of `progress`: its fraction is the received bytes over the expected length (0 while unknown).
  private let bodyProgress = Progress(totalUnitCount: -1)
  /// Foundation's client-side size hints. They are stored for compatibility and do not change the transfer.
  public var countOfBytesClientExpectsToSend: Int64 = -1
  public var countOfBytesClientExpectsToReceive: Int64 = -1
  /// Foundation's per-task delegate. Its `didSendBodyData` reports upload progress for this task's
  /// request body, and is read when the task is resumed.
  public var delegate: (any URLSessionTaskDelegate)?

  private let operation: @Sendable (URLSessionTask) async -> Void
  private var operationTask: Task<Void, Never>?
  private var operationGeneration: UInt64 = 0
  /// Foundation's delegate-based tasks (created without a completion handler) hear the receive callbacks and
  /// `didCompleteWithError`. A completion-handler task hears none of them.
  fileprivate let deliversDelegateCallbacks: Bool

  // `package`, not `fileprivate`: an open class copies the designated initializer into every module that inlines a
  // caller (cross-module optimization). A file-private copy is a strong symbol in each object, and Embedded Swift
  // links those objects together, so the duplicates fail in wasm-ld.
  package init(
    request: URLRequest,
    deliversDelegateCallbacks: Bool = false,
    operation: @escaping @Sendable (URLSessionTask) async -> Void
  ) {
    taskIdentifier = URLSessionTask.identifiers.withLock { $0 += 1; return $0 }
    self.request = request
    self.deliversDelegateCallbacks = deliversDelegateCallbacks
    self.operation = operation
    progress.addChild(bodyProgress, withPendingUnitCount: 95)
  }

  open func resume() {
    guard state == .suspended else { return }
    state = .running
    operationGeneration &+= 1
    let generation = operationGeneration
    operationTask = Task { [operation] in
      await operation(self)
      // A suspended task may be resumed while its previous operation is
      // unwinding. Only the current generation is allowed to transition to
      // completed; this keeps URLSessionTask state stable across suspend /
      // resume and cancellation races.
      guard self.operationGeneration == generation else { return }
      if self.state == .running { self.state = .completed }
    }
  }

  open func suspend() {
    guard state == .running else { return }
    state = .suspended
    operationGeneration &+= 1
    operationTask?.cancel()
    operationTask = nil
  }

  open func cancel() {
    guard state != .completed else { return }
    state = .canceling
    operationGeneration &+= 1
    operationTask?.cancel()
  }

  fileprivate func setProgress(sent: Int64? = nil, expectedSend: Int64? = nil) {
    if let sent { countOfBytesSent = sent }
    if let expectedSend { countOfBytesExpectedToSend = expectedSend }
  }

  /// Records the receive side. An expected length the body has already passed is unknown: a compressed body
  /// is counted after decoding, so its header length can be exceeded.
  fileprivate func setReceiveProgress(received: Int64, expected: Int64) {
    let total = expected >= 0 && received > expected ? -1 : expected
    countOfBytesReceived = received
    countOfBytesExpectedToReceive = total
    // The response has arrived, so its 5 units are done; the body's share follows the bytes received.
    progress.completedUnitCount = 5
    bodyProgress.totalUnitCount = total
    bodyProgress.completedUnitCount = received
  }

  /// Foundation completes `progress` when the task finishes successfully.
  fileprivate func finishReceiveProgress() {
    progress.completedUnitCount = progress.totalUnitCount
  }

  fileprivate func setResponse(_ response: URLResponse) { self.response = response }
}

open class URLSessionDataTask: URLSessionTask, @unchecked Sendable {}
public final class URLSessionUploadTask: URLSessionDataTask, @unchecked Sendable {}
public final class URLSessionDownloadTask: URLSessionTask, @unchecked Sendable {}

public final class URLSessionWebSocketTask: URLSessionTask, @unchecked Sendable {
  public enum CloseCode: Int, Sendable, Hashable {
    case invalid = 0
    case normalClosure = 1000
    case goingAway = 1001
    case protocolError = 1002
    case unsupportedData = 1003
    case noStatusReceived = 1005
    case abnormalClosure = 1006
    case invalidFramePayloadData = 1007
    case policyViolation = 1008
    case messageTooBig = 1009
    case mandatoryExtensionMissing = 1010
    case internalServerError = 1011
    case tlsHandshakeFailure = 1015
  }

  /// Foundation's `URLSessionWebSocketTask.Message`.
  public enum Message: Sendable, Equatable {
    case data(Data)
    case string(String)
  }

  // The connect observer task runs off the caller's executor on native hosts,
  // so the connection state is read and written under a lock.
  private let connectionLock = _RuntimeLock()
  private var _connectionTask: Task<WebSocketConnection, Error>?
  private var _connectionFailure: Error?
  private var _connection: WebSocketConnection?
  private var connectionTask: Task<WebSocketConnection, Error>? {
    get { connectionLock.withLock { _connectionTask } }
    set { connectionLock.withLock { _connectionTask = newValue } }
  }
  private var connectionFailure: Error? {
    get { connectionLock.withLock { _connectionFailure } }
    set { connectionLock.withLock { _connectionFailure = newValue } }
  }
  private var connection: WebSocketConnection? {
    get { connectionLock.withLock { _connection } }
    set { connectionLock.withLock { _connection = newValue } }
  }
  private let sessionConfiguration: URLSessionConfiguration

  fileprivate init(request: URLRequest, configuration: URLSessionConfiguration) {
    sessionConfiguration = configuration
    super.init(request: request) { _ in
      // Keep the URLSessionTask in its running state for the lifetime of the
      // socket. Cancellation of the base task interrupts this sleeper.
      while !Task.isCancelled {
        try? await _networkSleep(nanoseconds: 3_600_000_000_000)
      }
    }
  }

  /// Browser/WebSocket ready state. The inherited `URLSessionTask.state`
  /// remains the Foundation task lifecycle; this value reflects the socket's
  /// CONNECTING/OPEN/CLOSING/CLOSED state when the browser exposes it.
  package var webSocketState: WebSocketConnectionState {
    if let connection { return connection.stateOperation() }
    switch state {
    case .suspended, .completed: return .closed
    case .canceling: return .closing
    case .running: return .connecting
    }
  }

  /// The terminal close code, or `.invalid` until the browser reports one.
  /// Foundation exposes this as a non-optional value; preserving that shape
  /// keeps call sites portable while still allowing the richer `closeInfo`
  /// metadata through the browser-neutral connection.
  public var closeCode: CloseCode {
    guard let info = connection?.closeInfoOperation() else {
      return .invalid
    }
    return CloseCode(rawValue: info.code) ?? .invalid
  }

  public var closeReason: Data? { connection?.closeInfoOperation().flatMap { info in info.reason } }
  /// Browser close metadata, including `wasClean`, which Foundation's
  /// `closeCode`/`closeReason` pair does not expose.
  package var closeInfo: WebSocketCloseInfo? { connection?.closeInfoOperation() }
  package var negotiatedProtocol: String? { connection?.negotiatedProtocol }

  override public func resume() {
    guard state == .suspended else { return }
    super.resume()
    // Suspending a Foundation task must not create a second browser socket
    // when the existing connection is still alive. Browser WebSockets cannot
    // be paused at the protocol layer, so they remain connected while the
    // task's scheduling state is suspended.
    if connection != nil { return }
    if connectionTask == nil {
      connectionTask = Task { [request = self.request, configuration = sessionConfiguration] in
        try await NetworkRuntime.webSocket(request, configuration: configuration)
      }
    }
    guard let connectionTask else { return }
    Task { [self] in
      do {
        self.connection = try await connectionTask.value
        self.connectionTask = nil
      }
      catch {
        self.connectionFailure = error
        self.cancel()
      }
    }
  }

  public func send(_ message: URLSessionWebSocketTask.Message) async throws {
    try await _urlOperation(request) {
      try ensureUsable()
      let connection = try await resolvedConnection()
      guard !Task.isCancelled else { throw NetworkError.cancelled }
      try await connection.sendOperation(message)
    }
  }

  @preconcurrency public func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void) {
    Task {
      do { try await send(message); completionHandler(nil) }
      catch { completionHandler(_urlError(error, failingURL: self.request.url)) }
    }
  }

  public func receive() async throws -> URLSessionWebSocketTask.Message {
    try await _urlOperation(request) {
      try ensureUsable()
      let connection = try await resolvedConnection()
      return try await connection.receiveOperation()
    }
  }

  @preconcurrency public func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
    Task {
      do { completionHandler(.success(try await receive())) }
      catch { completionHandler(.failure(_urlError(error, failingURL: self.request.url))) }
    }
  }

  /// Sends a WebSocket control-frame ping when the installed host transport
  /// supports it. Browsers deliberately do not expose control-frame APIs, so
  /// the standard browser adapter reports `NetworkError.unsupported` rather
  /// than pretending an application message is a ping.
  public func sendPing() async throws {
    try await _urlOperation(request) {
      try ensureUsable()
      let connection = try await resolvedConnection()
      guard let ping = connection.pingOperation else {
        throw NetworkError.unsupported("WebSocket control-frame ping is unavailable in browsers")
      }
      try await ping()
    }
  }

  public func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
    Task {
      do {
        try await sendPing()
        pongReceiveHandler(nil)
      } catch {
        pongReceiveHandler(_urlError(error, failingURL: self.request.url))
      }
    }
  }

  override public func cancel() {
    connectionTask?.cancel()
    connection?.closeOperation(1000, nil)
    super.cancel()
  }

  public func cancel(with closeCode: CloseCode, reason: Data? = nil) {
    connectionTask?.cancel()
    connection?.closeOperation(closeCode.rawValue, reason)
    super.cancel()
  }

  /// A failed connection cancels the task; callers then see why it failed
  /// rather than a bare cancellation, whichever of them runs first.
  private func ensureUsable() throws {
    if let connectionFailure { throw connectionFailure }
    guard state != .canceling, state != .completed, !Task.isCancelled else {
      throw NetworkError.cancelled
    }
  }

  private func resolvedConnection() async throws -> WebSocketConnection {
    if let connection { return connection }
    guard let connectionTask else { throw NetworkError.unsupported("WebSocket task was not resumed") }
    let connection = try await connectionTask.value
    self.connection = connection
    self.connectionTask = nil
    return connection
  }
}

/// Foundation's `URLSessionDelegate`, without the Objective-C protocol. Session-level delegates are not
/// supported; per-task and per-call delegates are.
public protocol URLSessionDelegate: AnyObject, Sendable {}

/// Foundation's `URLSessionTaskDelegate`. Only the upload-progress callback is provided: browsers do not
/// expose redirect, authentication or metrics hooks, and the browser transport reports upload progress
/// through this method. Each callback's `bytesSent` is the increase since the previous callback.
public protocol URLSessionTaskDelegate: URLSessionDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64)
  /// Called once when a delegate-based task finishes, with the error that ended it (nil on success).
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
  /// Receive-side callbacks for a data task. Underscored, so not part of the API: `URLSessionDataDelegate` supplies
  /// the implementation, and the runtime routes each event through it without a dynamic protocol cast.
  func _urlSessionDataEvent(_ event: _URLSessionReceiveEvent, session: URLSession, task: URLSessionTask)
  /// Receive-side callbacks for a download task, supplied by `URLSessionDownloadDelegate` (underscored, as above).
  func _urlSessionDownloadEvent(_ event: _URLSessionReceiveEvent, session: URLSession, task: URLSessionTask)
}

extension URLSessionTaskDelegate {
  public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {}
  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {}
  public func _urlSessionDataEvent(_ event: _URLSessionReceiveEvent, session: URLSession, task: URLSessionTask) {}
  public func _urlSessionDownloadEvent(_ event: _URLSessionReceiveEvent, session: URLSession, task: URLSessionTask) {}
}

/// A receive-side event of one task. `.received` carries the bytes that just arrived (a buffered body arrives once,
/// whole), the cumulative count and the expected total (-1 when unknown).
public enum _URLSessionReceiveEvent: Sendable {
  case received(Data, totalReceived: Int64, expected: Int64)
  case finishedDownloading(URL)
}

/// Foundation's `URLSessionDataDelegate`, for a data task created with `dataTask(with:)`. `didReceive data` is called
/// once for each chunk of the body as it arrives. Browsers offer no redirect or response-disposition hook, so the
/// response is always allowed and the redirect policy is the configuration's.
public protocol URLSessionDataDelegate: URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
}

extension URLSessionDataDelegate {
  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {}

  public func _urlSessionDataEvent(_ event: _URLSessionReceiveEvent, session: URLSession, task: URLSessionTask) {
    guard case .received(let data, _, _) = event, let dataTask = task as? URLSessionDataTask else { return }
    urlSession(session, dataTask: dataTask, didReceive: data)
  }
}

/// Foundation's `URLSessionDownloadDelegate`, for a download task created with `downloadTask(with:)`. Each chunk
/// reports `didWriteData`; the finished body is reported once through `didFinishDownloadingTo`.
public protocol URLSessionDownloadDelegate: URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL)
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
}

extension URLSessionDownloadDelegate {
  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {}

  public func _urlSessionDownloadEvent(_ event: _URLSessionReceiveEvent, session: URLSession, task: URLSessionTask) {
    guard let downloadTask = task as? URLSessionDownloadTask else { return }
    switch event {
    case .received(let data, let totalReceived, let expected):
      urlSession(session, downloadTask: downloadTask, didWriteData: Int64(data.count), totalBytesWritten: totalReceived, totalBytesExpectedToWrite: expected)
    case .finishedDownloading(let location):
      urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
    }
  }
}

/// Foundation's `Content-Length` rule for `expectedContentLength`: the header's value, or -1 when it is absent or
/// the body is encoded (the header then counts encoded bytes, and the body delivered is decoded).
public func _expectedContentLength(headers: [String: String]) -> Int64 {
  var length: Int64 = -1
  var encoded = false
  for (name, value) in headers {
    switch name.lowercased() {
    // A negative or non-numeric length is unknown (-1), as Apple reports it.
    case "content-length": length = Int64(value).flatMap { $0 >= 0 ? $0 : nil } ?? -1
    case "content-encoding": encoded = encoded || (!value.isEmpty && value.lowercased() != "identity")
    default: break
    }
  }
  return encoded ? -1 : length
}

/// Turns the cumulative upload counts reported by a transport into Foundation's `didSendBodyData` deltas.
/// Counts that do not advance are ignored, and the total never exceeds the body size.
private final class _UploadProgressReporter: @unchecked Sendable {
  private let lock = _RuntimeLock()
  private var sent: Int64 = 0
  private let total: Int64
  private let deliver: @Sendable (_ totalSent: Int64, _ bytesSent: Int64) -> Void

  init(total: Int64, deliver: @escaping @Sendable (_ totalSent: Int64, _ bytesSent: Int64) -> Void) {
    self.total = total
    self.deliver = deliver
  }

  func update(totalSent: Int64) {
    let change = lock.withLock { () -> (Int64, Int64)? in
      let newTotal = min(max(totalSent, sent), total)
      guard newTotal > sent else { return nil }
      let delta = newTotal - sent
      sent = newTotal
      return (newTotal, delta)
    }
    if let change { deliver(change.0, change.1) }
  }

  /// Reports the whole body as sent. It runs when the transport has no progress hook, and once a
  /// response arrives, so every delegate ends at the expected total.
  func complete() { update(totalSent: total) }
}

public final class URLSession: @unchecked Sendable {
  public static let shared = URLSession()
  public let configuration: URLSessionConfiguration

  public init(configuration: URLSessionConfiguration = .default) {
    self.configuration = configuration
  }

  @_disfavoredOverload public func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url))
  }

  /// The upload reporter for `delegate`, when the request has a body to report.
  private func _uploadReporter(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)?,
    task: URLSessionTask?
  ) -> _UploadProgressReporter? {
    guard let delegate, let body = request.httpBody, !body.isEmpty else { return nil }
    let reportedTask = _progressTask(task, for: request)
    let total = Int64(body.count)
    return _UploadProgressReporter(total: total) { [self] totalSent, bytesSent in
      reportedTask.setProgress(sent: totalSent, expectedSend: total)
      delegate.urlSession(
        self,
        task: reportedTask,
        didSendBodyData: bytesSent,
        totalBytesSent: totalSent,
        totalBytesExpectedToSend: total
      )
    }
  }

  @_disfavoredOverload public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await _urlOperation(request) { try await _data(for: request, delegate: nil, task: nil) }
  }

  /// Foundation's `data(for:delegate:)`. `delegate` receives upload progress for the request body.
  public func data(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)? = nil
  ) async throws -> (Data, URLResponse) {
    try await _urlOperation(request) { try await _data(for: request, delegate: delegate, task: nil) }
  }

  /// Foundation's `data(from:delegate:)`.
  public func data(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url), delegate: delegate)
  }

  /// Runs a data request. A task passed in is the one the delegate hears about, so the completion-handler
  /// APIs keep their task's counters and delegate.
  private func _data(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)?,
    task: URLSessionTask?
  ) async throws -> (Data, URLResponse) {
    // A task whose delegate takes the body as it arrives streams it, so each chunk reaches `didReceive data`.
    // A request with a body keeps the buffered path, whose transport reports the upload.
    if let task, let receiver = _receiver(task), request.httpBody == nil, _urlProtocolType(for: request) == nil {
      let (stream, response) = try await _bytes(for: request, delegate: receiver, task: task)
      var data = Data()
      for try await chunk in stream { data.append(contentsOf: chunk) }
      return (data, response)
    }
    // Foundation reports upload progress to a delegate-based task and to the async calls, never to a task that has a
    // completion handler, whatever its delegate is.
    let uploadDelegate = (task?.deliversDelegateCallbacks ?? true) ? delegate : nil
    let reporter = _uploadReporter(for: request, delegate: uploadDelegate, task: task)
    var progress = NetworkRuntime.TransferProgress()
    if let reporter {
      progress.upload = { totalSent, _ in reporter.update(totalSent: totalSent) }
    }
    if let task {
      progress.download = { received, expected in task.setReceiveProgress(received: received, expected: expected) }
    }
    // Without a reporter the request takes the ordinary transports, as it did before progress was reported.
    let result = try await _dataCore(for: request, progress: progress.upload == nil && progress.download == nil ? nil : progress)
    reporter?.complete()
    if let task {
      task.setReceiveProgress(received: Int64(result.0.count), expected: result.1.expectedContentLength)
      if let receiver = _receiver(task), !result.0.isEmpty {
        // The transport delivered the body whole, so the delegate hears it once.
        _deliverReceive(
          .received(result.0, totalReceived: Int64(result.0.count), expected: result.1.expectedContentLength),
          delegate: receiver,
          task: task
        )
      }
    }
    return result
  }

  /// Hands a receive event to the task's delegate. Data tasks hear `didReceive data`; download tasks hear
  /// `didWriteData` and `didFinishDownloadingTo`. Each protocol ignores the task kinds it does not serve.
  private func _deliverReceive(
    _ event: _URLSessionReceiveEvent,
    delegate: any URLSessionTaskDelegate,
    task: URLSessionTask
  ) {
    delegate._urlSessionDataEvent(event, session: self, task: task)
    delegate._urlSessionDownloadEvent(event, session: self, task: task)
  }

  /// The delegate that hears a task's receive callbacks: only a delegate-based task has one.
  private func _receiver(_ task: URLSessionTask?) -> (any URLSessionTaskDelegate)? {
    guard let task, task.deliversDelegateCallbacks else { return nil }
    return task.delegate
  }

  /// Reports a delegate-based task's end, as Foundation's `didCompleteWithError` does.
  private func _deliverCompletion(_ task: URLSessionTask, error: (any Error)?) {
    guard task.deliversDelegateCallbacks, let delegate = task.delegate else { return }
    delegate.urlSession(self, task: task, didCompleteWithError: error.map { _urlError($0, failingURL: task.originalRequest?.url) })
  }

  private func _dataCore(
    for request: URLRequest,
    progress: NetworkRuntime.TransferProgress?
  ) async throws -> (Data, URLResponse) {
    if let protocolType = _urlProtocolType(for: request) {
      // A registered protocol answers the request under the same timeout and cancellation as the transports.
      return try await _raceRequest(for: request) {
        try await self._loadThroughURLProtocol(protocolType, request: request)
      }
    }
    guard let url = request.url, !url.absoluteString.isEmpty else {
      throw URLError(.badURL)
    }
    let result: (Data, HTTPURLResponse) = try await _raceRequest(for: request) {
      try await NetworkRuntime.perform(request, configuration: self.configuration, progress: progress)
    }
    return (result.0, result.1)
  }

  /// Runs `operation` (a transport, or a protocol class) under the request's timeout and task cancellation: a timeout or a
  /// cancelled task fails the request and the late result is discarded. Embedded builds leave both to the browser
  /// transport, which owns fetch cancellation and delivers the Foundation-shaped result directly.
  private func _raceRequest<Value: Sendable>(
    for request: URLRequest,
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
#if hasFeature(Embedded)
    // Embedded Swift already runs on the browser event loop. Spawning a
    // second timeout/race task here would enqueue work on the same host
    // executor and can keep a continuation suspended until another host tick.
    return try await operation()
#else
    let requestTimeout = request.explicitTimeout ?? configuration.timeoutIntervalForRequest
    let resourceTimeout = configuration.timeoutIntervalForResource > 0 ? configuration.timeoutIntervalForResource : requestTimeout
    let timeout = min(requestTimeout, resourceTimeout)
    guard timeout > 0, timeout.isFinite else {
      return try await operation()
    }
    let nanoseconds = _timeoutNanoseconds(timeout)
    let race = _NetworkRequestRace<Value>()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
        race.setContinuation(continuation)
        race.setTransportTask(Task {
          do {
            race.finish(.success(try await operation()))
          } catch {
            race.finish(.failure(error))
          }
        })
        if let cancelTimer = NetworkRuntime.scheduleTimeout(timeout, callback: {
          race.finish(.failure(NetworkError.timedOut))
        }) {
          race.setTimeoutCancellation(cancelTimer)
        } else {
          race.setTimeoutTask(Task {
            do {
              try await _networkSleep(nanoseconds: nanoseconds)
              race.finish(.failure(NetworkError.timedOut))
            } catch {
              // Cancellation is expected after the transport finishes.
            }
          })
        }
      }
    }, onCancel: {
      race.cancel()
    })
#endif
  }

  public func dataTask(
    with request: URLRequest,
    completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
  ) -> URLSessionDataTask {
    URLSessionDataTask(request: request) { [self] task in
      do {
        let (data, response) = try await self._data(for: request, delegate: task.delegate, task: task)
        task.setResponse(response)
        task.finishReceiveProgress()
        completionHandler(data, response, nil)
      } catch {
        completionHandler(nil, nil, _urlError(error, failingURL: request.url))
      }
    }
  }

  public func dataTask(
    with url: URL,
    completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
  ) -> URLSessionDataTask {
    dataTask(with: URLRequest(url: url), completionHandler: completionHandler)
  }

  /// Foundation's `dataTask(with:)`: a delegate-based task with no completion handler. Its delegate hears each chunk
  /// of the body (`didReceive data`) and then `didCompleteWithError`.
  public func dataTask(with request: URLRequest) -> URLSessionDataTask {
    URLSessionDataTask(request: request, deliversDelegateCallbacks: true) { [self] task in
      do {
        let (_, response) = try await self._data(for: request, delegate: task.delegate, task: task)
        task.setResponse(response)
        task.finishReceiveProgress()
        self._deliverCompletion(task, error: nil)
      } catch {
        self._deliverCompletion(task, error: error)
      }
    }
  }

  public func dataTask(with url: URL) -> URLSessionDataTask {
    dataTask(with: URLRequest(url: url))
  }

  /// Foundation's `downloadTask(with:)`: a delegate-based task with no completion handler. Its delegate hears
  /// `didWriteData` for each chunk, `didFinishDownloadingTo`, and then `didCompleteWithError`.
  public func downloadTask(with request: URLRequest) -> URLSessionDownloadTask {
    URLSessionDownloadTask(request: request, deliversDelegateCallbacks: true) { [self] task in
      do {
        let (_, response) = try await self._download(for: request, delegate: task.delegate, task: task)
        task.setResponse(response)
        task.finishReceiveProgress()
        self._deliverCompletion(task, error: nil)
      } catch {
        self._deliverCompletion(task, error: error)
      }
    }
  }

  public func downloadTask(with url: URL) -> URLSessionDownloadTask {
    downloadTask(with: URLRequest(url: url))
  }

  public func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
    try await _urlOperation(request) { try await _bytes(for: request, delegate: nil, task: nil) }
  }

  /// Foundation's `bytes(for:delegate:)`. Streamed transports report no upload progress, so `delegate`
  /// receives one callback, once the response headers arrive.
  public func bytes(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)? = nil
  ) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
    try await _urlOperation(request) { try await _bytes(for: request, delegate: delegate, task: nil) }
  }

  private func _bytes(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)?,
    task: URLSessionTask?
  ) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
    let reporter = _uploadReporter(for: request, delegate: delegate, task: task)
    // Apply the request timeout while waiting for response headers as well as
    // while consuming the body.  A fetch can otherwise remain pending before
    // `Response.body` is available (for example during a CORS preflight).
    let (response, source) = try await performStreamingWithTimeout(request)
    reporter?.complete()
    let expected = response.expectedContentLength
    task?.setReceiveProgress(received: 0, expected: expected)
    let stream = AsyncThrowingStream<Data, Error> { continuation in
      let race = _NetworkStreamRace(failingURL: request.url)
      race.setContinuation(continuation)
      // Install termination before starting the producer so a caller that
      // cancels immediately after receiving the stream cannot leave a body
      // task or browser reader running.
      continuation.onTermination = { [race] _ in race.cancel() }
      race.setBodyTask(Task {
        var received: Int64 = 0
        do {
          for try await chunk in source {
            try _networkCheckCancellation()
            received += Int64(chunk.count)
            if let task {
              task.setReceiveProgress(received: received, expected: expected)
              if let receiver = self._receiver(task) {
                self._deliverReceive(.received(chunk, totalReceived: received, expected: expected), delegate: receiver, task: task)
              }
            }
            race.yield(chunk)
          }
          race.finish()
        } catch is CancellationError {
          race.finish(NetworkError.cancelled)
        } catch {
          race.finish(error)
        }
      })
      let requestTimeout = request.explicitTimeout ?? configuration.timeoutIntervalForRequest
      let resourceTimeout = configuration.timeoutIntervalForResource > 0 ? configuration.timeoutIntervalForResource : requestTimeout
      let timeout = min(requestTimeout, resourceTimeout)
      if timeout > 0, timeout.isFinite {
        if let cancelTimer = NetworkRuntime.scheduleTimeout(timeout, callback: { race.timeOut() }) {
          race.setTimeoutCancellation(cancelTimer)
        } else {
          let nanoseconds = _timeoutNanoseconds(timeout)
          race.setTimeoutTask(Task {
            do {
              try await _networkSleep(nanoseconds: nanoseconds)
              race.timeOut()
            } catch { }
          })
        }
      }
    }
    return (stream, response)
  }

  private func performStreamingWithTimeout(
    _ request: URLRequest
  ) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
    let requestTimeout = request.explicitTimeout ?? configuration.timeoutIntervalForRequest
    let resourceTimeout = configuration.timeoutIntervalForResource > 0 ? configuration.timeoutIntervalForResource : requestTimeout
    let timeout = min(requestTimeout, resourceTimeout)
    guard timeout > 0, timeout.isFinite else {
      return try await NetworkRuntime.performStreaming(request, configuration: configuration)
    }

    let nanoseconds = _timeoutNanoseconds(timeout)
    // `isolation: nil` is what the `#isolation` default argument gives in this nonisolated method. It is written out
    // because Embedded Swift serializes the default argument's macro expansion at a different place on some compiles,
    // which changed this target's `.swiftmodule` without a source change and rebuilt everything that imports it
    // (Documentation/Performance/BUILD_TIME.md, "The development loop").
    return try await withThrowingTaskGroup(
      of: (HTTPURLResponse, AsyncThrowingStream<Data, Error>).self, isolation: nil
    ) { group in
      group.addTask {
        try await NetworkRuntime.performStreaming(request, configuration: self.configuration)
      }
      group.addTask {
        try await _networkSleep(nanoseconds: nanoseconds)
        throw NetworkError.timedOut
      }
      defer { group.cancelAll() }
      return try _requireGroupResult(try await group.next())
    }
  }

  public func bytes(from url: URL) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
    try await bytes(for: URLRequest(url: url))
  }

  /// Foundation's `bytes(from:delegate:)`.
  public func bytes(
    from url: URL,
    delegate: (any URLSessionTaskDelegate)? = nil
  ) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse) {
    try await bytes(for: URLRequest(url: url), delegate: delegate)
  }

  /// Foundation's `upload(for:from:delegate:)`. `delegate` receives upload progress for `bodyData`.
  public func upload(
    for request: URLRequest,
    from bodyData: Data,
    delegate: (any URLSessionTaskDelegate)? = nil
  ) async throws -> (Data, URLResponse) {
    var request = request
    request.httpBody = bodyData
    return try await data(for: request, delegate: delegate)
  }

  @_disfavoredOverload public func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
    try await upload(for: request, from: bodyData, delegate: nil)
  }

  /// Browsers only expose request streaming when the server and browser both
  /// support `ReadableStream` uploads. The default adapter aggregates chunks
  /// into one body so callers retain a portable API; browser hosts may install
  /// a specialized transport later without changing this signature.
  package func upload(for request: URLRequest, from bodyStream: AsyncThrowingStream<Data, Error>) async throws -> (Data, URLResponse) {
    var body = Data()
    for try await chunk in bodyStream {
      body.append(contentsOf: chunk)
    }
    return try await upload(for: request, from: body)
  }

  public func uploadTask(
    with request: URLRequest,
    from bodyData: Data,
    completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
  ) -> URLSessionUploadTask {
    URLSessionUploadTask(request: request) { [self] task in
      do {
        var uploadRequest = request
        uploadRequest.httpBody = bodyData
        let (data, response) = try await self._data(for: uploadRequest, delegate: task.delegate, task: task)
        task.setProgress(sent: Int64(bodyData.count), expectedSend: Int64(bodyData.count))
        task.setResponse(response)
        task.finishReceiveProgress()
        completionHandler(data, response, nil)
      } catch { completionHandler(nil, nil, _urlError(error, failingURL: request.url)) }
    }
  }

  /// Foundation's `uploadTask(with:from:)`: a delegate-based upload with no completion handler. Its delegate hears
  /// `didSendBodyData` as the body is sent, then `didCompleteWithError`.
  public func uploadTask(with request: URLRequest, from bodyData: Data) -> URLSessionUploadTask {
    URLSessionUploadTask(request: request, deliversDelegateCallbacks: true) { [self] task in
      do {
        var uploadRequest = request
        uploadRequest.httpBody = bodyData
        let (_, response) = try await self._data(for: uploadRequest, delegate: task.delegate, task: task)
        task.setProgress(sent: Int64(bodyData.count), expectedSend: Int64(bodyData.count))
        task.setResponse(response)
        task.finishReceiveProgress()
        self._deliverCompletion(task, error: nil)
      } catch {
        self._deliverCompletion(task, error: error)
      }
    }
  }

  /// Returns a browser object URL when the host can materialize one. A host
  /// without a file API returns the response URL; the bytes remain available
  /// through `data(for:)` and no fake filesystem path is created.
  public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
    try await _urlOperation(request) { try await _download(for: request, delegate: nil, task: nil) }
  }

  /// Foundation's `download(for:delegate:)`. The browser has no download progress event; `delegate`
  /// receives upload progress for a request body only. Read `countOfBytesReceived` on a task, or count the
  /// chunks of `bytes(for:)`, to follow the download.
  public func download(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)? = nil
  ) async throws -> (URL, URLResponse) {
    try await _urlOperation(request) { try await _download(for: request, delegate: delegate, task: nil) }
  }

  public func download(from url: URL) async throws -> (URL, URLResponse) {
    try await download(for: URLRequest(url: url))
  }

  /// Foundation's `download(from:delegate:)`.
  public func download(from url: URL, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
    try await download(for: URLRequest(url: url), delegate: delegate)
  }

  private func _download(
    for request: URLRequest,
    delegate: (any URLSessionTaskDelegate)?,
    task: URLSessionTask?
  ) async throws -> (URL, URLResponse) {
    // Consume the same stream used by `bytes(for:)` so downloads can report
    // receive progress as chunks arrive.  The runtime's fallback transport
    // still yields one chunk when Streams are unavailable.
    let (stream, response) = try await _bytes(for: request, delegate: delegate, task: task)
    var data = Data()
    for try await chunk in stream {
      data.append(contentsOf: chunk)
    }
    let materialized = (response as? HTTPURLResponse).flatMap {
      NetworkRuntime.materializeDownload(data, response: $0)
    }
    let location = try _downloadLocation(materialized: materialized, responseURL: response.url)
    if let task, let receiver = _receiver(task) {
      _deliverReceive(.finishedDownloading(location), delegate: receiver, task: task)
    }
    return (location, response)
  }

  public func downloadTask(
    with request: URLRequest,
    completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void
  ) -> URLSessionDownloadTask {
    URLSessionDownloadTask(request: request) { [self] task in
      do {
        let (url, response) = try await self._download(for: request, delegate: task.delegate, task: task)
        task.setResponse(response)
        task.finishReceiveProgress()
        completionHandler(url, response, nil)
      } catch { completionHandler(nil, nil, _urlError(error, failingURL: request.url)) }
    }
  }

  public func downloadTask(
    with url: URL,
    completionHandler: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void
  ) -> URLSessionDownloadTask {
    downloadTask(with: URLRequest(url: url), completionHandler: completionHandler)
  }

  public func webSocketTask(with request: URLRequest) -> URLSessionWebSocketTask {
    URLSessionWebSocketTask(request: request, configuration: configuration)
  }

  public func webSocketTask(with url: URL) -> URLSessionWebSocketTask {
    webSocketTask(with: URLRequest(url: url))
  }

  public func webSocketTask(with url: URL, protocols: [String]) -> URLSessionWebSocketTask {
    var request = URLRequest(url: url)
    request.webSocketProtocols = protocols
    return webSocketTask(with: request)
  }
}


/// A timeout in nanoseconds, saturated: Double(UInt64.max) rounds up to 2^64, so the product of a huge timeout and 1e9
/// would reach it and trap UInt64(_:). Past 1.8e10 seconds (570 years) the wait is as good as forever.
func _timeoutNanoseconds(_ seconds: Double) -> UInt64 {
  guard seconds.isFinite, seconds > 0 else { return 0 }
  return seconds >= 1.8e10 ? UInt64.max : UInt64(seconds * 1_000_000_000)
}
