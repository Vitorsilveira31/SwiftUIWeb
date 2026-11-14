import Foundation
import Testing
@testable import SwiftUIWebNetworking

/// Apple's test seam: a URLProtocol subclass listed in `protocolClasses` answers the requests it accepts, and the
/// session never reaches the transport for them.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var requestedURLs: [String] = []

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "stub.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    StubURLProtocol.requestedURLs.append(url.absoluteString)
    if url.path == "/fail" {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
      return
    }
    let response = HTTPURLResponse(url: url, statusCode: 201, headerFields: ["Content-Type": "text/plain"], expectedContentLength: 4)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("sta".utf8))
    client?.urlProtocol(self, didLoad: Data("ub".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized, .processGlobalState)
struct URLProtocolStubTests {
  private func session() -> URLSession {
    var configuration = URLSessionConfiguration()
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  @Test
  func configuredProtocolClassAnswersTheRequestWithItsClientCallbacks() async throws {
    StubURLProtocol.requestedURLs = []
    let (data, response) = try await session().data(from: URL(string: "https://stub.test/hello")!)
    #expect(String(decoding: data, as: UTF8.self) == "staub")
    #expect(response.mimeType == nil)
    #expect((response as? HTTPURLResponse)?.statusCode == 201)
    #expect(StubURLProtocol.requestedURLs == ["https://stub.test/hello"])
  }

  @Test
  func clientFailureIsThrownToTheCaller() async throws {
    do {
      _ = try await session().data(from: URL(string: "https://stub.test/fail")!)
      Issue.record("A failing protocol must fail the request")
    } catch let error as URLError {
      #expect(error.code == .cannotConnectToHost)
    }
  }

  @Test
  func globallyRegisteredProtocolClassAppliesToEverySession() async throws {
    StubURLProtocol.requestedURLs = []
    #expect(URLProtocol.registerClass(StubURLProtocol.self))
    defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
    let (data, _) = try await URLSession(configuration: URLSessionConfiguration()).data(from: URL(string: "https://stub.test/global")!)
    #expect(String(decoding: data, as: UTF8.self) == "staub")
  }

  @Test
  func clientCallbacksWithDefaultImplementationsAreAcceptedSilently() async throws {
    var configuration = URLSessionConfiguration()
    configuration.protocolClasses = [CallbackURLProtocol.self]
    let (data, response) = try await URLSession(configuration: configuration).data(from: URL(string: "https://callbacks.test/x")!)
    #expect(String(decoding: data, as: UTF8.self) == "callback")
    #expect((response as? HTTPURLResponse)?.statusCode == 202)
  }

  @Test
  func protocolThatFinishesWithoutAResponseFailsAsBadServerResponse() async throws {
    var configuration = URLSessionConfiguration()
    configuration.protocolClasses = [CallbackURLProtocol.self]
    do {
      _ = try await URLSession(configuration: configuration).data(from: URL(string: "https://empty.test/x")!)
      Issue.record("A protocol that never reports a response must fail the request")
    } catch let error as URLError {
      #expect(error.code == .badServerResponse)
    }
  }

  @Test
  func baseURLProtocolDeclinesRequestsAndLoadsNothing() {
    let plain = URLRequest(url: URL(string: "https://base.test/x")!)
    #expect(URLProtocol.canInit(with: plain) == false)
    let plainTask = URLSessionDataTask(request: plain) { _ in }
    #expect(URLProtocol.canInit(with: plainTask) == false)

    let stubTask = URLSessionDataTask(request: URLRequest(url: URL(string: "https://stub.test/x")!)) { _ in }
    #expect(StubURLProtocol.canInit(with: stubTask) == true)
    #expect(StubURLProtocol.canInit(with: plainTask) == false)
    #expect(StubURLProtocol.canInit(with: URLSessionDataTask(request: URLRequest(url: URL(string: "https://stub.test/x")!)) { _ in }) == true)

    #expect(URLProtocol.canonicalRequest(for: plain) == plain)
    var post = plain
    post.method = .post
    #expect(URLProtocol.requestIsCacheEquivalent(plain, to: plain))
    #expect(URLProtocol.requestIsCacheEquivalent(plain, to: post) == false)

    let client = RecordingURLProtocolClient()
    let base = URLProtocol(request: plain, cachedResponse: nil, client: client)
    base.startLoading()
    base.stopLoading()
    #expect(client.events.isEmpty)
    #expect(base.client === client)
  }

  @Test
  func registeringAProtocolClassTwiceKeepsOneCopy() {
    defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
    #expect(URLProtocol.registerClass(StubURLProtocol.self))
    #expect(URLProtocol.registerClass(StubURLProtocol.self))
    #expect(URLProtocol._registeredClasses.filter { $0 == StubURLProtocol.self }.count == 1)
    URLProtocol.unregisterClass(StubURLProtocol.self)
    #expect(!URLProtocol._registeredClasses.contains { $0 == StubURLProtocol.self })
  }

  @Test
  func cachedResponseKeepsItsResponseDataAndPolicy() {
    let response = URLResponse(url: URL(string: "https://cache.test/x")!, mimeType: nil, expectedContentLength: 6, textEncodingName: nil)
    let stored = CachedURLResponse(response: response, data: Data("cached".utf8), storagePolicy: .allowedInMemoryOnly)
    #expect(stored.response === response)
    #expect(stored.data == Data("cached".utf8))
    #expect(stored.storagePolicy == .allowedInMemoryOnly)
    #expect(CachedURLResponse(response: response, data: Data()).storagePolicy == .allowed)
  }
}

/// Answers `callbacks.test` through the client callbacks that have default implementations, and fails
/// `empty.test` by finishing without ever reporting a response.
private final class CallbackURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "callbacks.test" || request.url?.host == "empty.test"
  }

  override func startLoading() {
    guard let url = request.url else { return }
    if url.host == "empty.test" {
      client?.urlProtocolDidFinishLoading(self)
      return
    }
    let interim = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
    client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: interim)
    client?.urlProtocol(self, cachedResponseIsValid: CachedURLResponse(response: interim, data: Data()))
    let response = HTTPURLResponse(url: url, statusCode: 202, headerFields: [:], expectedContentLength: 8)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("callback".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
}

/// Records which callbacks a protocol reported, for the base class's no-op methods.
private final class RecordingURLProtocolClient: URLProtocolClient {
  var events: [String] = []

  func urlProtocol(_ protocol: URLProtocol, didReceive response: URLResponse, cacheStoragePolicy policy: URLCache.StoragePolicy) {
    events.append("response")
  }

  func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
    events.append("data")
  }

  func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
    events.append("finished")
  }

  func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error) {
    events.append("failed")
  }
}
