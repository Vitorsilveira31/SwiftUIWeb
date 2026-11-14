// Apple's URL loading seam: applications stub networking in tests by subclassing URLProtocol and listing the
// subclass in URLSessionConfiguration.protocolClasses (or registering it with URLProtocol.registerClass). The
// session asks each class, in order, whether it canInit(with:) the request; the first one that does loads the
// request through its client callbacks instead of the browser transport. Natively this file is not used: the
// Foundation types are exported instead (see SwiftUIWeb/Exports.swift).

@_spi(Renderer) import SwiftUIWebLocking
@_spi(Renderer) import SwiftUIWebTransferable

/// The cache policy a loaded response is stored with. Applications that stub networking report `.notAllowed`.
public final class URLCache: @unchecked Sendable {
  public enum StoragePolicy: UInt, Sendable {
    case allowed
    case allowedInMemoryOnly
    case notAllowed
  }
}

/// A response and body a protocol class hands back for caching. The stand-in does not cache; it exists so the
/// `URLProtocolClient` signatures match Apple's.
public final class CachedURLResponse: @unchecked Sendable {
  public let response: URLResponse
  public let data: Data
  public let storagePolicy: URLCache.StoragePolicy

  public init(response: URLResponse, data: Data, storagePolicy: URLCache.StoragePolicy = .allowed) {
    self.response = response
    self.data = data
    self.storagePolicy = storagePolicy
  }
}

/// The callbacks a `URLProtocol` subclass reports its progress through.
public protocol URLProtocolClient: AnyObject {
  func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse)
  func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse)
  func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy)
  func urlProtocol(_ protocol: URLProtocol, didLoad data: Data)
  func urlProtocolDidFinishLoading(_ protocol: URLProtocol)
  func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error)
}

public extension URLProtocolClient {
  func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {}
  func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {}
}

/// Apple's base class for custom loaders. Subclasses override `canInit(with:)`, `canonicalRequest(for:)`,
/// `startLoading()` and `stopLoading()`, and report through `client`.
open class URLProtocol: @unchecked Sendable {
  private static let registry = _Locked<[AnyClass]>([])

  public let request: URLRequest
  public let cachedResponse: CachedURLResponse?
  public let client: URLProtocolClient?

  public required init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
    self.request = request
    self.cachedResponse = cachedResponse
    self.client = client
  }

  open class func canInit(with request: URLRequest) -> Bool { false }

  open class func canInit(with task: URLSessionTask) -> Bool {
    guard let request = task.currentRequest else { return false }
    return canInit(with: request)
  }

  open class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  open class func requestIsCacheEquivalent(_ first: URLRequest, to second: URLRequest) -> Bool {
    first.url == second.url && first.httpMethod == second.httpMethod
  }

  open func startLoading() {}

  open func stopLoading() {}

  /// Makes `protocolClass` consulted by every session, after its configuration's `protocolClasses`.
  open class func registerClass(_ protocolClass: AnyClass) -> Bool {
    registry.withLock { classes in
      if !classes.contains(where: { $0 == protocolClass }) { classes.append(protocolClass) }
      return true
    }
  }

  open class func unregisterClass(_ protocolClass: AnyClass) {
    registry.withLock { classes in classes.removeAll { $0 == protocolClass } }
  }

  /// The globally registered protocol classes, in registration order.
  package static var _registeredClasses: [AnyClass] { registry.withLock { $0 } }
}

/// Collects one protocol's callbacks and resumes the waiting session request with them.
final class _URLProtocolLoader: URLProtocolClient, @unchecked Sendable {
  private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
  private var response: URLResponse?
  private var body = Data()
  private var finished = false

  func start(_ continuation: CheckedContinuation<(Data, URLResponse), Error>) {
    self.continuation = continuation
  }

  private func complete(_ result: Result<(Data, URLResponse), Error>) {
    guard !finished, let continuation else { return }
    finished = true
    self.continuation = nil
    continuation.resume(with: result)
  }

  func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
    self.response = response
  }

  func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
    body.append(contentsOf: data)
  }

  func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
    guard let response else {
      complete(.failure(URLError(.badServerResponse)))
      return
    }
    complete(.success((body, response)))
  }

  func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error) {
    complete(.failure(error))
  }
}

extension URLSession {
  /// The protocol class that answers `request`: the configuration's `protocolClasses`, then the globally registered
  /// ones. `nil` leaves the request to the browser transport.
  func _urlProtocolType(for request: URLRequest) -> URLProtocol.Type? {
    for candidate in (configuration.protocolClasses ?? []) + URLProtocol._registeredClasses {
      guard let type = _urlProtocolClass(candidate), type.canInit(with: request) else { continue }
      return type
    }
    return nil
  }

  /// The candidate as a `URLProtocol` subclass. Embedded Swift has no metatype dynamic casts (`as? URLProtocol.Type`
  /// would need `swift_dynamicCastMetatype`, which the target does not link), so there the class is reinterpreted.
  /// Apple's contract is what makes that sound: `protocolClasses` and `registerClass` take `URLProtocol` subclasses.
  @inline(__always)
  private func _urlProtocolClass(_ candidate: AnyClass) -> URLProtocol.Type? {
    #if hasFeature(Embedded)
    return unsafeBitCast(candidate, to: URLProtocol.Type.self)
    #else
    return candidate as? URLProtocol.Type
    #endif
  }

  /// Loads `request` through a protocol class, the way Foundation does: canonicalize, create, start, and wait for
  /// the client to finish or fail.
  func _loadThroughURLProtocol(
    _ type: URLProtocol.Type,
    request: URLRequest
  ) async throws -> (Data, URLResponse) {
    let loader = _URLProtocolLoader()
    let proto = type.init(request: type.canonicalRequest(for: request), cachedResponse: nil, client: loader)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
      loader.start(continuation)
      proto.startLoading()
    }
  }
}
