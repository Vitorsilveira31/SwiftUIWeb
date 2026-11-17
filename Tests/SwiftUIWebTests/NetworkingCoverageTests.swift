#if !os(WASI)
import Foundation
import Testing
@testable import SwiftUIWebNetworking
import SwiftUIWebUniformTypeIdentifiers
import SwiftUIWebTransferable

/// Clears every host hook the tests in this file install, so each test starts from the default host.
private func resetNetworkHooks() {
  NetworkRuntime.install(nil)
  NetworkRuntime.installConfigured(nil)
  NetworkRuntime.installStreaming(nil)
  NetworkRuntime.installTransferProgress(nil)
  NetworkRuntime.installDownloadMaterializer(nil)
}

/// A session whose requests have no timeout race, so the installed transport answers directly.
private func directSession() -> URLSession {
  URLSession(configuration: URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0))
}

private struct OpaqueTransportFailure: Error {}

@Suite struct URLRequestCachePolicyCoverageTests {
  @Test func deprecatedReloadIgnoringCacheDataMeansReloadIgnoringLocalCacheData() {
    #expect(URLRequest.CachePolicy.reloadIgnoringCacheData == .reloadIgnoringLocalCacheData)
    #expect(URLRequest.CachePolicy.reloadIgnoringCacheData.rawValue == 1)
  }
}

@Suite struct URLCredentialPasswordCoverageTests {
  @Test func hasPasswordIsTrueWhenAPasswordWasGiven() {
    let credential = URLCredential(user: "vitor", password: "secret")
    #expect(credential.hasPassword)
    #expect(credential.password == "secret")
  }

  @Test func hasPasswordIsTrueEvenForAnEmptyPassword() {
    #expect(URLCredential(user: "vitor", password: "").hasPassword)
  }
}

@Suite struct HTTPCookiePropertyKeyCoverageTests {
  @Test func rawValueInitializerKeepsTheBrowserKeySpelling() {
    let key = HTTPCookiePropertyKey(rawValue: "HttpOnly")
    #expect(key.rawValue == "HttpOnly")
    #expect(key == HTTPCookiePropertyKey("HttpOnly"))
    #expect(HTTPCookiePropertyKey(rawValue: "Name") == .name)
  }
}

@Suite struct URLErrorConversionCoverageTests {
  @Test func unrecognizedFailuresBecomeUnknownURLErrorKeepingTheURL() {
    let url = URL(string: "https://example.test/fail")!
    let converted = _urlError(OpaqueTransportFailure(), failingURL: url)
    #expect(converted.code == .unknown)
    #expect(converted.failingURL == url)
  }

  @Test func cancellationBecomesCancelledURLError() {
    #expect(_urlError(CancellationError()).code == .cancelled)
  }
}

@Suite struct UTTypeCodableCoverageTests {
  @Test func decodesFromItsIdentifierString() throws {
    let type = try JSONDecoder().decode(UTType.self, from: Data("\"public.png\"".utf8))
    #expect(type == UTType.png)
    #expect(type.identifier == "public.png")
  }

  @Test func encodesAsItsIdentifierString() throws {
    let data = try JSONEncoder().encode(UTType("com.example.report"))
    #expect(String(decoding: data, as: UTF8.self) == "\"com.example.report\"")
  }
}

/// Only the delegate methods a test does not override fall back to the protocol-extension defaults.
private final class QuietDataDelegate: URLSessionDataDelegate {}

private final class QuietDownloadDelegate: URLSessionDownloadDelegate {
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@Suite struct URLSessionDelegateDefaultsCoverageTests {
  @Test func defaultDataDelegateAcceptsReceivedChunksWithoutOverride() {
    let session = directSession()
    let task = session.dataTask(with: URL(string: "https://example.test/data")!)
    QuietDataDelegate().urlSession(session, dataTask: task, didReceive: Data("chunk".utf8))
  }

  @Test func defaultDownloadDelegateAcceptsWriteProgressWithoutOverride() {
    let session = directSession()
    let task = session.downloadTask(with: URL(string: "https://example.test/file")!)
    QuietDownloadDelegate().urlSession(
      session,
      downloadTask: task,
      didWriteData: 5,
      totalBytesWritten: 5,
      totalBytesExpectedToWrite: 10
    )
  }
}

@Suite(.serialized, .processGlobalState) struct NetworkRuntimeHookCoverageTests {
  @Test func requestTransportFlagFollowsRequestAndConfiguredTransports() {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    #expect(!NetworkRuntime.hasRequestTransport)

    NetworkRuntime.installConfigured { request, _ in (Data(), HTTPURLResponse(url: request.url!, statusCode: 204)) }
    #expect(NetworkRuntime.hasRequestTransport)

    NetworkRuntime.installConfigured(nil)
    #expect(!NetworkRuntime.hasRequestTransport)

    NetworkRuntime.install { request in (Data(), HTTPURLResponse(url: request.url!, statusCode: 204)) }
    #expect(NetworkRuntime.hasRequestTransport)
  }

  @Test func progressAndStreamingFlagsFollowTheirOwnInstallation() {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    #expect(!NetworkRuntime.hasTransferProgressTransport)
    #expect(!NetworkRuntime.hasStreamingTransport)

    NetworkRuntime.installTransferProgress { request, _, _ in (Data(), HTTPURLResponse(url: request.url!, statusCode: 200)) }
    NetworkRuntime.installStreaming { request, _ in
      (HTTPURLResponse(url: request.url!, statusCode: 200), AsyncThrowingStream<Data, Error> { $0.finish() })
    }
    #expect(NetworkRuntime.hasTransferProgressTransport)
    #expect(NetworkRuntime.hasStreamingTransport)

    NetworkRuntime.installTransferProgress(nil)
    #expect(!NetworkRuntime.hasTransferProgressTransport)
    #expect(NetworkRuntime.hasStreamingTransport)
  }

  @Suite struct URLSessionFromURLCoverageTests {
  private let url = URL(string: "https://example.test/resource")!

  @Test func dataFromURLWithDelegateReturnsTheTransportBody() async throws {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    NetworkRuntime.install { request in (Data("hello".utf8), HTTPURLResponse(url: request.url!, statusCode: 200)) }

    let (data, response) = try await directSession().data(from: url, delegate: nil)
    #expect(data == Data("hello".utf8))
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
  }

  @Test func bytesFromURLWithDelegateStreamsTheTransportBody() async throws {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    NetworkRuntime.install { request in (Data("hello".utf8), HTTPURLResponse(url: request.url!, statusCode: 200)) }

    let (stream, response) = try await directSession().bytes(from: url, delegate: nil)
    var collected = Data()
    for try await chunk in stream { collected.append(contentsOf: chunk) }
    #expect(collected == Data("hello".utf8))
    #expect(response.url == url)
  }

  @Test func downloadFromURLWithDelegateReturnsTheResponseURLWhenNothingIsMaterialized() async throws {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    NetworkRuntime.install { request in (Data("file".utf8), HTTPURLResponse(url: request.url!, statusCode: 200)) }

    let (location, response) = try await directSession().download(from: url, delegate: nil)
    #expect(location == url)
    #expect(response.url == url)
  }
  }
}

@Suite(.serialized, .processGlobalState) struct URLSessionWithoutDelegateCoverageTests {
  private let url = URL(string: "https://example.test/resource")!

  @Test func dataFromURLWithoutDelegateReturnsTheTransportBody() async throws {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    NetworkRuntime.install { request in (Data("hello".utf8), HTTPURLResponse(url: request.url!, statusCode: 200)) }

    // `data(from:)` without a delegate is a disfavored overload: a call picks `data(from:delegate:)`, a reference this one.
    let call: (URL) async throws -> (Data, URLResponse) = directSession().data(from:)
    let (data, response) = try await call(url)
    #expect(data == Data("hello".utf8))
    #expect((response as? HTTPURLResponse)?.statusCode == 200)
  }

  @Test func dataForRequestWithoutDelegateReturnsTheTransportBody() async throws {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    NetworkRuntime.install { request in (Data("body".utf8), HTTPURLResponse(url: request.url!, statusCode: 203)) }

    let call: (URLRequest) async throws -> (Data, URLResponse) = directSession().data(for:)
    let (data, response) = try await call(URLRequest(url: url))
    #expect(data == Data("body".utf8))
    #expect((response as? HTTPURLResponse)?.statusCode == 203)
  }

  @Test func uploadWithoutDelegateHandsTheBodyToTheTransport() async throws {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    final class SentBody: @unchecked Sendable { var data: Data? }
    let sent = SentBody()
    NetworkRuntime.install { request in
      sent.data = request.httpBody
      return (Data("stored".utf8), HTTPURLResponse(url: request.url!, statusCode: 201))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let call: (URLRequest, Data) async throws -> (Data, URLResponse) = directSession().upload(for:from:)
    let (data, response) = try await call(request, Data("payload".utf8))
    #expect(sent.data == Data("payload".utf8))
    #expect(data == Data("stored".utf8))
    #expect((response as? HTTPURLResponse)?.statusCode == 201)
  }

  @Test func requestWithAnEmptyURLFailsAsBadURL() async {
    defer { resetNetworkHooks() }
    resetNetworkHooks()
    // `URL(string:)` rejects "", so the empty URL is built as written.
    do {
      _ = try await directSession().data(for: URLRequest(url: URL("")))
      Issue.record("expected a bad URL error")
    } catch let error as URLError {
      #expect(error.code == .badURL)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }
}
#endif
