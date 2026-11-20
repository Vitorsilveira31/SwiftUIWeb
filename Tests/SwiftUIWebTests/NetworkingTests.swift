#if os(WASI)
import Foundation
import Testing
import SwiftUIWebNetworking

private func networkTestURL(_ string: String) -> URL { URL(string: string)! }

/// Deterministic host-side substitute for the browser's online/offline event
/// source. The production adapter is event driven; this probe lets the WASI
/// tests exercise the same lifecycle without a JavaScript runtime.
private final class ConnectivityTestProbe: @unchecked Sendable {
  var state: NetworkConnectivityState
  var subscriptionCount = 0
  var cancellationCount = 0
  var callback: (@Sendable (NetworkConnectivityState) -> Void)?
  var observedStates: [NetworkConnectivityState] = []

  init(state: NetworkConnectivityState) {
    self.state = state
  }

  func subscribe(
    _ callback: @escaping @Sendable (NetworkConnectivityState) -> Void
  ) -> (@Sendable () -> Void) {
    subscriptionCount += 1
    self.callback = callback
    return { [weak self] in
      guard let self else { return }
      self.cancellationCount += 1
      self.callback = nil
    }
  }

  func emit(_ state: NetworkConnectivityState) {
    self.state = state
    callback?(state)
  }

  func observe(_ state: NetworkConnectivityState) {
    observedStates.append(state)
  }
}

/// Removes every network host (see `ProcessGlobalStateTrait.tearDown`), before each test too: a suite that ran
/// earlier may leave the native adapter installed, and its transfer-progress transport took the uploads of a test
/// that installed only a configured transport (they reached the real network and failed to resolve the host).
@MainActor private func resetNetworkingHosts() {
  NetworkRuntime.install(nil)
  NetworkRuntime.installConfigured(nil)
  NetworkRuntime.installStreaming(nil)
  NetworkRuntime.installTransferProgress(nil)
  NetworkRuntime.installDownloadMaterializer(nil)
  NetworkRuntime.installWebSocket(nil)
  NetworkRuntime.installConnectivityProvider(nil)
  NetworkRuntime.installConnectivitySubscription(nil)
}

@Suite(.serialized, .processGlobalState(tearDown: resetNetworkingHosts))
@MainActor
final class NetworkingTests {
  init() { resetNetworkingHosts() }

  @Test
  func testRequestMethodsAndCaseInsensitiveHeaders() throws {
    var request = URLRequest(url: networkTestURL("http://127.0.0.1:8080/echo"))
    request.method = .post
    request.setValue("one", forHTTPHeaderField: "X-Test")
    request.addValue("two", forHTTPHeaderField: "x-test")
    _expectEqual(request.effectiveHTTPMethod, "POST")
    _expectEqual(request.value(forHTTPHeaderField: "X-TEST"), "one, two")
    _expectNoThrow(try request.validateForBrowser())
  }

  @Test
  func testDataAndStreamingTransports() async throws {
    NetworkRuntime.install { request in
      return (Data("{\"ok\":true}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: ["content-type": "application/json"]))
    }
    let (data, response) = try await URLSession.shared.data(from: networkTestURL("http://127.0.0.1:8080/json"))
    _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
    _expectEqual(data.utf8String(), "{\"ok\":true}")

    NetworkRuntime.installStreaming { request, _ in
      let stream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data("first\n".utf8))
        continuation.yield(Data("second\n".utf8))
        continuation.finish()
      }
      return (HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: ["content-length": "13"], expectedContentLength: 13), stream)
    }
    let (chunks, streamResponse) = try await URLSession.shared.bytes(for: URLRequest(url: networkTestURL("http://127.0.0.1:8080/stream")))
    var text = ""
    for try await chunk in chunks { text += chunk.utf8String() }
    _expectEqual(text, "first\nsecond\n")
    _expectEqual((streamResponse as? HTTPURLResponse)?.statusCode, 200)
  }

  @Test
  func testTaskCancellationAndConnectivity() async throws {
    NetworkRuntime.install { _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (Data(), HTTPURLResponse(url: networkTestURL("http://127.0.0.1:8080/slow"), statusCode: 200))
    }
    let task = URLSession.shared.dataTask(with: URLRequest(url: networkTestURL("http://127.0.0.1:8080/slow"))) { _, _, error in
      _expectTrue(error is SwiftUIWebNetworking.URLError)
    }
    task.resume()
    task.cancel()
    _expectEqual(task.state, .canceling)

    NetworkRuntime.installConnectivityProvider { NetworkConnectivityState(status: .online, effectiveType: "4g", downlinkMbps: 10, rttMilliseconds: 25) }
    _expectEqual(NetworkRuntime.connectivity.status, .online)
    _expectEqual(NetworkRuntime.connectivity.effectiveType, "4g")
  }

  @Test
  func testConnectivityMonitorTransitionsAndCleanup() async {
    let probe = ConnectivityTestProbe(state: NetworkConnectivityState(status: .online))
    NetworkRuntime.installConnectivityProvider { probe.state }
    NetworkRuntime.installConnectivitySubscription { callback in
      probe.subscribe(callback)
    }

    let monitor = NetworkConnectivityMonitor()
    monitor.pathUpdateHandler = { [probe] state in probe.observe(state) }
    monitor.start()

    _expectEqual(probe.subscriptionCount, 1)
    _expectEqual(probe.observedStates, [NetworkConnectivityState(status: .online)])
    _expectEqual(monitor.currentPath.pathStatus, .satisfied)
    _expectEqual(monitor.currentPath.isOnline, true)

    let stream = monitor.updates
    var iterator = stream.makeAsyncIterator()
    let initial = await iterator.next()
    _expectEqual(initial?.status, .online)

    // Duplicate browser events are harmless and should not create duplicate
    // path updates; a real transition is delivered to both APIs.
    probe.emit(NetworkConnectivityState(status: .online))
    _expectEqual(probe.observedStates.count, 1)
    probe.emit(NetworkConnectivityState(status: .offline))
    let changed = await iterator.next()
    _expectEqual(changed?.status, .offline)
    _expectEqual(monitor.currentPath.pathStatus, .unsatisfied)
    _expectEqual(monitor.currentPath.isOnline, false)
    _expectEqual(probe.observedStates.last?.status, .offline)

    monitor.cancel()
    _expectEqual(probe.cancellationCount, 1)
    probe.emit(NetworkConnectivityState(status: .online))
    _expectEqual(monitor.currentPath.status, .offline)
    _expectEqual(probe.observedStates.count, 2)

    // A second start creates a fresh browser subscription and receives the
    // current snapshot, matching NWPathMonitor's restartable lifecycle.
    monitor.start()
    _expectEqual(probe.subscriptionCount, 2)
    _expectEqual(probe.observedStates.last?.status, .offline)
    monitor.cancel()
    _expectEqual(probe.cancellationCount, 2)
  }

  @Test
  func testConnectivityStreamTerminationReleasesSubscription() async {
    let probe = ConnectivityTestProbe(state: NetworkConnectivityState(status: .unknown))
    NetworkRuntime.installConnectivityProvider { probe.state }
    NetworkRuntime.installConnectivitySubscription { callback in
      probe.subscribe(callback)
    }

    let monitor = NetworkConnectivityMonitor()
    let stream = monitor.updates
    _expectEqual(probe.subscriptionCount, 1)

    // Cancelling an awaiting consumer terminates AsyncStream and invokes its
    // onTermination hook. The monitor has no callback handler, so that hook
    // is enough to detach the browser listeners.
    let consumer = Task {
      var iterator = stream.makeAsyncIterator()
      _ = await iterator.next()
      while await iterator.next() != nil {}
    }
    await Task.yield()
    consumer.cancel()
    _ = await consumer.result
    await Task.yield()
    _expectEqual(probe.cancellationCount, 1)
  }

  @Test
  func testTimeoutAndBrowserRestrictions() async throws {
    var forbidden = URLRequest(url: networkTestURL("https://example.test/"))
    forbidden.setValue("secret", forHTTPHeaderField: "Cookie")
    _expectThrows(try forbidden.validateForBrowser()) { error in
      _expectEqual((error as? SwiftUIWebNetworking.URLError)?.code, .unknown)
    }

    NetworkRuntime.installConfigured { request, _ in
      try await Task.sleep(nanoseconds: 500_000_000)
      return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    let configuration = URLSessionConfiguration(
      timeoutIntervalForRequest: 0.01,
      timeoutIntervalForResource: 0.01
    )
    do {
      _ = try await URLSession(configuration: configuration).data(from: networkTestURL("https://example.test/slow"))
      _fail("Expected a timeout")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .timedOut)
    }
  }

  @Test
  func testWebSocketMessageBridge() async throws {
    NetworkRuntime.installWebSocket { request, _ in
      _expectEqual(request.url!.absoluteString, "wss://example.test/socket")
      _expectEqual(request.webSocketProtocols, ["swiftuiweb.test"])
      return WebSocketConnection(
        send: { _ in },
        receive: { .string("hello") },
        close: { _, _ in },
        state: { .open },
        closeInfo: { WebSocketCloseInfo(code: 1000, reason: Data("done".utf8), wasClean: true) },
        negotiatedProtocol: "swiftuiweb.test"
      )
    }
    let task = URLSession.shared.webSocketTask(
      with: networkTestURL("wss://example.test/socket"),
      protocols: ["swiftuiweb.test"]
    )
    task.resume()
    try await task.send(.string("ping"))
    _expectEqual(try await task.receive(), .string("hello"))
    _expectEqual(task.webSocketState, .open)
    _expectEqual(task.negotiatedProtocol, "swiftuiweb.test")
    do {
      try await task.sendPing()
      _fail("Browser-compatible transports must not fake control-frame pings")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unsupportedURL)
    }
    task.cancel(with: .normalClosure, reason: Data("done".utf8))
    _expectEqual(task.closeCode, .normalClosure)
    _expectEqual(task.closeReason?.utf8String(), "done")
    _expectEqual(task.closeInfo?.wasClean, true)
  }
}
#endif

#if !os(WASI)
/// Leaves the request transport a test just installed as the only host: no streaming, transfer-progress or download
/// host another test installed reaches this test's requests.
@MainActor private func keepOnlyTheRequestTransport() {
  NetworkRuntime.installStreaming(nil)
  NetworkRuntime.installTransferProgress(nil)
  NetworkRuntime.installDownloadMaterializer(nil)
}

import Foundation
import Testing
@testable import SwiftUIWebNetworking
import SwiftUIWebWeb


private final class NativeNetworkTimerProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var callback: (@Sendable () -> Void)?
  private var cancellationCount = 0

  func schedule(_ callback: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
    lock.lock()
    self.callback = callback
    lock.unlock()
    return { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.cancellationCount += 1
      self.callback = nil
      self.lock.unlock()
    }
  }

  func fire() {
    lock.lock()
    let callback = self.callback
    lock.unlock()
    callback?()
  }

  var cancellations: Int {
    lock.lock()
    defer { lock.unlock() }
    return cancellationCount
  }
}

/// Native equivalent of the browser online/offline event source. Keeping this
/// probe in the native suite exercises the same monitor lifecycle that the
/// WASI fixture covers, so the Foundation build cannot silently regress while
/// only the Embedded path is tested.
private final class NativeConnectivityTestProbe: @unchecked Sendable {
  var state: NetworkConnectivityState
  var subscriptionCount = 0
  var cancellationCount = 0
  var callback: (@Sendable (NetworkConnectivityState) -> Void)?
  var observedStates: [NetworkConnectivityState] = []

  init(state: NetworkConnectivityState) {
    self.state = state
  }

  func subscribe(
    _ callback: @escaping @Sendable (NetworkConnectivityState) -> Void
  ) -> (@Sendable () -> Void) {
    subscriptionCount += 1
    self.callback = callback
    return { [weak self] in
      guard let self else { return }
      self.cancellationCount += 1
      self.callback = nil
    }
  }

  func emit(_ state: NetworkConnectivityState) {
    self.state = state
    callback?(state)
  }

  func observe(_ state: NetworkConnectivityState) {
    observedStates.append(state)
  }
}

/// Removes what the suite's tests install, inside the global-state gate after each test (`ProcessGlobalStateTrait`).
/// A `deinit` would run whenever the instance is released, possibly while the next test holds the gate.
@MainActor private func resetNativeFacadeHosts() {
  NetworkRuntime.install(nil)
  NetworkRuntime.installConfigured(nil)
  NetworkRuntime.installStreaming(nil)
  NetworkRuntime.installDownloadMaterializer(nil)
  NetworkRuntime.installWebSocket(nil)
  NetworkRuntime.installConnectivityProvider(nil)
  NetworkRuntime.installConnectivitySubscription(nil)
  NetworkRuntime.installTimeoutScheduler(nil)
  NetworkRuntime.installTransferProgress(nil)
}

@Suite(.serialized, .processGlobalState(tearDown: resetNativeFacadeHosts))
@MainActor
final class NativeNetworkingFacadeTests {
  @Test
  func testNativeAndEmbeddedFacadeUseTheSameAsyncAPI() async throws {
    NetworkRuntime.installConfigured { request, _ in
      (
        Data("native".utf8),
        HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: ["x-host": "native"])
      )
    }
    let (data, response) = try await URLSession.shared.data(
      from: URL(string: "https://example.test/native")!
    )
    _expectEqual(data.utf8String(), "native")
    _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
  }

  @Test
  func testLegacyTransportAndURLConvenienceOverloadsShareTheAsyncContract() async throws {
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installStreaming(nil)
    NetworkRuntime.installDownloadMaterializer(nil)
    NetworkRuntime.installTimeoutScheduler(nil)
    NetworkRuntime.install { request in
      let body = request.httpBody?.utf8String() ?? "legacy"
      return (
        Data(body.utf8),
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          expectedContentLength: Int64(body.utf8.count)
        )
      )
    }
    keepOnlyTheRequestTransport()

    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    let url = URL(string: "https://example.test/legacy")!

    let (direct, directResponse) = try await session.data(from: url)
    _expectEqual(direct.utf8String(), "legacy")
    _expectEqual((directResponse as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)

    let taskExpectation = _makeExpectation()
    let dataTask = session.dataTask(with: url) { data, response, error in
      _expectNil(error)
      _expectEqual(data?.utf8String(), "legacy")
      _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
      taskExpectation.fulfill()
    }
    dataTask.resume()
    await _fulfillment(of: [taskExpectation], timeout: 1)
    _expectEqual(dataTask.state, .completed)

    let (bytes, bytesResponse) = try await session.bytes(from: url)
    var collected = Data()
    for try await chunk in bytes { collected.append(contentsOf: chunk) }
    _expectEqual(collected.utf8String(), "legacy")
    _expectEqual((bytesResponse as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)

    var uploadRequest = URLRequest(url: URL(string: "https://example.test/legacy-upload")!)
    uploadRequest.method = .post
    let (uploaded, _) = try await session.upload(
      for: uploadRequest,
      from: Data("payload".utf8)
    )
    _expectEqual(uploaded.utf8String(), "payload")

    let bodyStream = AsyncThrowingStream<Data, Error> { continuation in
      continuation.yield(Data("stream".utf8))
      continuation.finish()
    }
    let (streamUpload, _) = try await session.upload(for: uploadRequest, from: bodyStream)
    _expectEqual(streamUpload.utf8String(), "stream")

    let (downloadURL, downloadResponse) = try await session.download(from: url)
    _expectEqual(downloadURL.absoluteString, url.absoluteString)
    _expectEqual((downloadResponse as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
  }

  @Test
  func testTransportFailuresAndUnsupportedCapabilitiesFailDeterministically() async {
    NetworkRuntime.install(nil)
    NetworkRuntime.installStreaming(nil)
    NetworkRuntime.installWebSocket(nil)
    NetworkRuntime.installConfigured { _, _ in
      throw NetworkError.unavailable
    }

    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )

    do {
      _ = try await session.data(from: URL(string: "https://example.test/unavailable")!)
      _fail("A session without a transport must fail")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .resourceUnavailable)
    } catch {
      _fail("Expected URLError code unavailable")
    }

    let socket = session.webSocketTask(with: URL(string: "wss://example.test/unavailable")!)
    socket.resume()
    do {
      try await socket.send(.string("hello"))
      _fail("A socket without a host transport must fail")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unsupportedURL)
    } catch {
      _fail("Expected the browser-compatible unsupported error")
    }
  }

  @Test
  func testCustomTimeoutSchedulerCancelsTransportAndTimer() async {
    final class Counter: @unchecked Sendable {
      private let lock = NSLock()
      private(set) var callbackCount = 0
      private(set) var cancellationCount = 0

      func callback() {
        lock.lock()
        callbackCount += 1
        lock.unlock()
      }

      func cancelled() {
        lock.lock()
        cancellationCount += 1
        lock.unlock()
      }
    }

    let counter = Counter()
    NetworkRuntime.installConfigured { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    NetworkRuntime.installTimeoutScheduler { _, callback in
      callback()
      counter.callback()
      return {
        counter.cancelled()
      }
    }

    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 1,
        timeoutIntervalForResource: 1
      )
    )
    do {
      _ = try await session.data(from: URL(string: "https://example.test/timeout")!)
      _fail("The host timer should win the transport race")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .timedOut)
    } catch {
      _fail("Expected URLError code timedOut")
    }
    _expectEqual(counter.callbackCount, 1)
    _expectEqual(counter.cancellationCount, 1)
  }

  @Test
  func testStreamingFailureTimeoutAndCancellationCleanup() async {
    NetworkRuntime.installStreaming { request, _ in
      let source = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data("partial".utf8))
        continuation.finish(throwing: NetworkError.transport("stream failed"))
      }
      return (HTTPURLResponse(url: request.url!, statusCode: 200), source)
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    let failedStream: AsyncThrowingStream<Data, Error>
    do {
      (failedStream, _) = try await session.bytes(
        from: URL(string: "https://example.test/stream-failure")!
      )
    } catch {
      _fail("The response headers should succeed before the body fails")
      return
    }
    var iterator = failedStream.makeAsyncIterator()
    let firstChunk = try? await iterator.next()
    _expectEqual(firstChunk?.utf8String(), "partial")
    do {
      _ = try await iterator.next()
      _fail("The stream failure must be surfaced to the consumer")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unknown)
    } catch {
      _fail("Expected the transport stream error")
    }

    final class StreamHolder: @unchecked Sendable {
      var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    }
    let holder = StreamHolder()
    NetworkRuntime.installStreaming { request, _ in
      let source = AsyncThrowingStream<Data, Error> { continuation in
        holder.continuation = continuation
      }
      return (HTTPURLResponse(url: request.url!, statusCode: 200), source)
    }
    let timeoutSession = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0.01,
        timeoutIntervalForResource: 0.01
      )
    )
    let timedStream: AsyncThrowingStream<Data, Error>
    do {
      (timedStream, _) = try await timeoutSession.bytes(
        from: URL(string: "https://example.test/stream-timeout")!
      )
    } catch {
      _fail("The response headers should succeed before the body timeout")
      return
    }
    do {
      var timedIterator = timedStream.makeAsyncIterator()
      _ = try await timedIterator.next()
      _fail("The body timeout must terminate an idle stream")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .timedOut)
    } catch {
      _fail("Expected URLError code timedOut")
    }

    NetworkRuntime.installStreaming { request, _ in
      let source = AsyncThrowingStream<Data, Error> { continuation in
        continuation.finish(throwing: CancellationError())
      }
      return (HTTPURLResponse(url: request.url!, statusCode: 200), source)
    }
    let cancellationSession = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    do {
      let (cancelledStream, _) = try await cancellationSession.bytes(
        from: URL(string: "https://example.test/stream-cancellation")!
      )
      var cancelledIterator = cancelledStream.makeAsyncIterator()
      _ = try await cancelledIterator.next()
      _fail("A cancelled stream source must not finish successfully")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    } catch {
      _fail("Stream-source cancellation must normalize to URLError code cancelled")
    }
  }

  @Test
  func testStreamingTimeoutSchedulerCleansUpEvenWhenItFiresDuringInstallation() async {
    let timer = NativeNetworkTimerProbe()
    NetworkRuntime.installTimeoutScheduler { _, callback in
      let cancellation = timer.schedule(callback)
      timer.fire()
      return cancellation
    }
    NetworkRuntime.installStreaming { request, _ in
      let source = AsyncThrowingStream<Data, Error> { _ in }
      return (HTTPURLResponse(url: request.url!, statusCode: 200), source)
    }

    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 1,
        timeoutIntervalForResource: 1
      )
    )
    do {
      let (stream, _) = try await session.bytes(
        from: URL(string: "https://example.test/stream-scheduled-timeout")!
      )
      var iterator = stream.makeAsyncIterator()
      _ = try await iterator.next()
      _fail("The installed host timer must terminate the body stream")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .timedOut)
    } catch {
      _fail("Expected the host timer to produce URLError code timedOut")
    }
    _expectEqual(timer.cancellations, 1)
  }

  @Test
  func testStreamingResponseHeaderTimeoutCancelsThePendingTransport() async {
    NetworkRuntime.installStreaming { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (HTTPURLResponse(url: request.url!, statusCode: 200), AsyncThrowingStream { $0.finish() })
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0.01,
        timeoutIntervalForResource: 0.01
      )
    )
    do {
      _ = try await session.bytes(from: URL(string: "https://example.test/headers-timeout")!)
      _fail("A response-header timeout must fail before returning a stream")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .timedOut)
    } catch {
      _fail("Expected URLError code timedOut while waiting for stream headers")
    }
  }

  @Test
  func testCancelledAsyncRequestNormalizesCancellation() async {
    NetworkRuntime.installConfigured { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 10,
        timeoutIntervalForResource: 10
      )
    )
    let requestTask = Task {
      try await session.data(from: URL(string: "https://example.test/cancel")!)
    }
    await Task.yield()
    requestTask.cancel()
    do {
      _ = try await requestTask.value
      _fail("Cancellation must interrupt the request")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    } catch {
      _fail("Expected URLError code cancelled")
    }
  }

  /// Cancelling right as the request installs its continuation used to lose
  /// the wake-up about once in twenty runs and suspend the task forever. The
  /// race is timing-dependent, so the scenario is repeated; the time limit
  /// turns a lost wake-up into a failure instead of a hung suite.
  @Test(.timeLimit(.minutes(1)))
  func testCancellationRacingTheContinuationNeverLosesTheWakeUp() async {
    NetworkRuntime.installConfigured { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 10,
        timeoutIntervalForResource: 10
      )
    )
    for iteration in 0..<200 {
      let requestTask = Task {
        try await session.data(from: URL(string: "https://example.test/cancel-race")!)
      }
      // Alternate between cancelling before and after the first suspension
      // so both orderings around the continuation are exercised.
      if iteration % 2 == 0 { await Task.yield() }
      requestTask.cancel()
      do {
        _ = try await requestTask.value
        _fail("Cancellation must interrupt the request")
      } catch let error as SwiftUIWebNetworking.URLError {
        _expectEqual(error.code, .cancelled)
      } catch {
        _fail("Expected URLError code cancelled")
      }
    }
  }

  @Test
  func testAsyncRequestTimeoutUsesTheNativeClockWithoutHostScheduler() async {
    NetworkRuntime.installTimeoutScheduler(nil)
    NetworkRuntime.installConfigured { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0.01,
        timeoutIntervalForResource: 0.01
      )
    )
    do {
      _ = try await session.data(from: URL(string: "https://example.test/native-timeout")!)
      _fail("The native clock must time out a stalled request")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .timedOut)
    } catch {
      _fail("Expected URLError code timedOut from the native clock")
    }
  }

  @Test
  func testLegacyStreamingAndWebSocketCancellationNormalizeCancellation() async {
    NetworkRuntime.install { _ in throw CancellationError() }
    NetworkRuntime.installConfigured(nil)
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    do {
      _ = try await session.data(from: URL(string: "https://example.test/legacy-cancel")!)
      _fail("Legacy cancellation must not be swallowed")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    } catch {
      _fail("Expected URLError code cancelled from the legacy transport")
    }

    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured { _, _ in throw CancellationError() }
    do {
      _ = try await session.data(from: URL(string: "https://example.test/configured-cancel")!)
      _fail("Configured cancellation must not be swallowed")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    } catch {
      _fail("Expected URLError code cancelled from the configured transport")
    }

    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installStreaming { _, _ in throw CancellationError() }
    do {
      _ = try await session.bytes(from: URL(string: "https://example.test/stream-cancel")!)
      _fail("Streaming cancellation must not be swallowed")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    } catch {
      _fail("Expected URLError code cancelled from the streaming transport")
    }

    NetworkRuntime.installStreaming(nil)
    NetworkRuntime.installWebSocket { _, _ in throw CancellationError() }
    let socket = session.webSocketTask(
      with: URL(string: "wss://example.test/socket-cancel")!
    )
    socket.resume()
    do {
      try await socket.send(.string("cancel"))
      _fail("WebSocket cancellation must not be swallowed")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    } catch {
      _fail("Expected URLError code cancelled from the WebSocket transport")
    }
  }

  @Test
  func testConnectivityMonitorUsesTheSameLifecycleOnNativeHosts() async {
    let probe = NativeConnectivityTestProbe(
      state: NetworkConnectivityState(
        status: .online,
        effectiveType: "4g",
        downlinkMbps: 20,
        rttMilliseconds: 12
      )
    )
    NetworkRuntime.installConnectivityProvider { probe.state }
    NetworkRuntime.installConnectivitySubscription { callback in
      probe.subscribe(callback)
    }

    let monitor = NetworkConnectivityMonitor()
    _expectEqual(monitor.currentState.status, .online)
    _expectEqual(monitor.currentPath.pathStatus, .satisfied)
    monitor.pathUpdateHandler = { [probe] state in probe.observe(state) }
    monitor.start()
    monitor.start()
    _expectEqual(probe.subscriptionCount, 1)
    _expectEqual(probe.observedStates.count, 1)

    // Setting the alias after start immediately publishes the current path.
    monitor.updateHandler = { [probe] state in probe.observe(state) }
    _expectEqual(monitor.updateHandler != nil, true)
    _expectEqual(probe.observedStates.count, 2)
    probe.emit(
      NetworkConnectivityState(
        status: .online,
        effectiveType: "4g",
        downlinkMbps: 20,
        rttMilliseconds: 12
      )
    )
    _expectEqual(probe.observedStates.count, 2)
    probe.emit(NetworkConnectivityState(status: .offline))
    _expectEqual(probe.observedStates.last?.status, .offline)
    _expectEqual(monitor.currentPath.isOnline, false)

    let stream = monitor.updates
    var iterator = stream.makeAsyncIterator()
    let initial = await iterator.next()
    _expectEqual(initial?.status, .offline)
    probe.emit(NetworkConnectivityState(status: .unknown))
    let changed = await iterator.next()
    _expectEqual(changed?.status, .unknown)
    _expectEqual(monitor.currentState.pathStatus, .unknown)

    monitor.updateHandler = nil
    monitor.cancel()
    _expectEqual(probe.cancellationCount, 1)
    let finished = await iterator.next()
    _expectNil(finished)
    monitor.cancel()

    // A stopped monitor can be started again and receives a fresh snapshot.
    probe.emit(NetworkConnectivityState(status: .online))
    monitor.start()
    _expectEqual(probe.subscriptionCount, 2)
    _expectEqual(monitor.currentPath.status, .online)
    monitor.cancel()
    _expectEqual(probe.cancellationCount, 2)
    NetworkRuntime.installConnectivityProvider(nil)
    NetworkRuntime.installConnectivitySubscription(nil)
  }

  @Test
  func testConnectivityUpdatesWithoutHostSubscriptionUseSnapshotAndNoopCleanup() async {
    NetworkRuntime.installConnectivityProvider(nil)
    NetworkRuntime.installConnectivitySubscription(nil)
    let monitor = NetworkConnectivityMonitor()
    var updates = monitor.updates.makeAsyncIterator()
    let initial = await updates.next()
    _expectEqual(initial?.status, .unknown)
    monitor.cancel()
    _expectEqual(monitor.currentState.status, .unknown)
  }

  @Test
  func testRequestConfigurationResponseAndProgressContracts() throws {
    var request = URLRequest(url: URL(string: "https://example.test/resource")!)
    _expectEqual(request.effectiveHTTPMethod, "GET")
    request.setBasicAuthentication(user: "alice", password: "secret")
    _expectEqual(request.value(forHTTPHeaderField: "authorization"), "Basic YWxpY2U6c2VjcmV0")
    _expectNoThrow(try request.validateForBrowser())

    request.httpBody = Data("body".utf8)
    _expectThrows(try request.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("HTTP GET requests cannot contain a body"))
    }
    request.method = .post
    request.setValue("x", forHTTPHeaderField: "Sec-Fetch-Site")
    _expectThrows(try request.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .forbiddenHeader("Sec-Fetch-Site"))
    }

    var configuration = URLSessionConfiguration(timeoutIntervalForRequest: .nan)
    _expectThrows(try configuration.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("Session timeout intervals must be finite and non-negative"))
    }
    configuration = URLSessionConfiguration(httpAdditionalHeaders: ["Cookie": "secret"])
    _expectThrows(try configuration.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .forbiddenHeader("Cookie"))
    }

    let response = SwiftUIWebNetworking.HTTPURLResponse(
      url: request.url!,
      statusCode: 404,
      headerFields: ["Content-Type": "text/plain"],
      expectedContentLength: 4,
      mimeType: "text/plain",
      textEncodingName: "utf-8",
      httpVersion: "HTTP/2"
    )
    _expectFalse(response.isSuccess)
    _expectTrue(response.isClientError)
    _expectEqual(response.value(forHTTPHeaderField: "content-type"), "text/plain")
    _expectEqual(response.expectedContentLength, 4)
    _expectEqual(response.httpVersion, "HTTP/2")

    _expectEqual(NetworkError.cancelled.description, "The network request was cancelled")
    _expectEqual(NetworkError.timedOut.description, "The network request timed out")
    _expectEqual(URLCredential(user: "u", password: "p").persistence, .none)
  }

  @Test
  func testRequestPolicyAndValidationMatrix() throws {
    var request = URLRequest(
      url: URL(string: "https://example.test/policies")!,
      cachePolicy: SwiftUIWebNetworking.URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData,
      timeoutInterval: 2
    )
    _expectEqual(request.cachePolicy, SwiftUIWebNetworking.URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData)
    _expectEqual(request.timeoutInterval, 2, accuracy: 0)
    request.mainDocumentURL = URL(string: "https://example.test/")
    _expectEqual(request.mainDocumentURL?.absoluteString, "https://example.test/")

    for method in HTTPMethod.allCases {
      request.method = method
      _expectEqual(request.method, method)
      _expectEqual(request.effectiveHTTPMethod, method.rawValue)
    }
    request.httpMethod = "patch"
    _expectEqual(request.method, SwiftUIWebNetworking.HTTPMethod.patch)
    request.method = nil
    _expectEqual(request.effectiveHTTPMethod, "GET")

    // Header lookup is ASCII case-insensitive, while a different-length name
    // must remain a separate field instead of being folded accidentally.
    request.setValue("one", forHTTPHeaderField: "X-Test")
    request.setValue("two", forHTTPHeaderField: "x-test")
    _expectEqual(request.allHTTPHeaderFields?.count, 1)
    _expectEqual(request.value(forHTTPHeaderField: "X-TEST"), "two")
    request.setValue("long", forHTTPHeaderField: "X-Testing")
    _expectEqual(request.allHTTPHeaderFields?.count, 2)
    request.setValue(nil, forHTTPHeaderField: "X-TEST")
    let removedHeader: String? = request.value(forHTTPHeaderField: "x-test")
    _expectNil(removedHeader)
    request.addValue("first", forHTTPHeaderField: "X-List")
    request.addValue("second", forHTTPHeaderField: "x-list")
    _expectEqual(request.value(forHTTPHeaderField: "X-LIST"), "first, second")
    request.setValue(nil, forHTTPHeaderField: "missing")

    var invalid = URLRequest(url: request.url!)
    invalid.timeoutInterval = -.leastNonzeroMagnitude
    _expectThrows(try invalid.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("Request timeout interval must be finite and non-negative"))
    }
    invalid = URLRequest(url: request.url!)
    invalid.httpMethod = "bad method"
    _expectThrows(try invalid.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("HTTP method is not a valid token"))
    }
    invalid = URLRequest(url: request.url!)
    invalid.method = SwiftUIWebNetworking.HTTPMethod.head
    invalid.httpBody = Data("body".utf8)
    _expectThrows(try invalid.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("HTTP HEAD requests cannot contain a body"))
    }
    for method in ["CONNECT", "TRACE", "TRACK"] {
      invalid = URLRequest(url: request.url!)
      invalid.httpMethod = method
      _expectThrows(try invalid.validateForBrowser()) { error in
        _expectEqual(error as? NetworkError, .unsupported("The browser fetch API does not permit HTTP \(method) requests"))
      }
    }
    for field in ["Proxy-Authorization", "Sec-Fetch-Site"] {
      invalid = URLRequest(url: request.url!)
      invalid.setValue("x", forHTTPHeaderField: field)
      _expectThrows(try invalid.validateForBrowser()) { error in
        _expectEqual(error as? NetworkError, .forbiddenHeader(field))
      }
    }
    invalid = URLRequest(url: request.url!)
    invalid.webSocketProtocols = ["chat", "chat"]
    _expectThrows(try invalid.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("WebSocket subprotocols must be valid HTTP tokens"))
    }
    invalid.webSocketProtocols = ["bad protocol"]
    _expectThrows(try invalid.validateForBrowser()) { error in
      _expectEqual(error as? NetworkError, .invalidRequest("WebSocket subprotocols must be valid HTTP tokens"))
    }
    invalid.webSocketProtocols = ["chat", "superchat"]
    _expectNoThrow(try invalid.validateForBrowser())

    let validConfiguration = SwiftUIWebNetworking.URLSessionConfiguration(
      timeoutIntervalForRequest: 0,
      timeoutIntervalForResource: 0,
      httpAdditionalHeaders: ["X-Test": "ok"],
      requestCachePolicy: SwiftUIWebNetworking.URLRequest.CachePolicy.returnCacheDataElseLoad,
      redirectPolicy: .manual,
      credentialsPolicy: .include
    )
    _expectNoThrow(try validConfiguration.validateForBrowser())
    _expectEqual(SwiftUIWebNetworking.URLSessionConfiguration.default.requestCachePolicy, .useProtocolCachePolicy)
    _expectEqual(SwiftUIWebNetworking.URLSessionConfiguration.ephemeral.credentialsPolicy, .sameOrigin)
    // Cookies follow Foundation's switches: either one off sends the request with credentials omitted.
    var cookieRequest = SwiftUIWebNetworking.URLRequest(url: SwiftUIWebNetworking.URL(string: "https://api.example.com/me")!)
    let including = SwiftUIWebNetworking.URLSessionConfiguration(credentialsPolicy: .include)
    _expectEqual(including.credentialsPolicy(for: cookieRequest), .include)
    cookieRequest.httpShouldHandleCookies = false
    _expectEqual(including.credentialsPolicy(for: cookieRequest), .omit)
    cookieRequest.httpShouldHandleCookies = true
    _expectEqual(SwiftUIWebNetworking.URLSessionConfiguration(credentialsPolicy: .include, httpShouldSetCookies: false).credentialsPolicy(for: cookieRequest), .omit)
  }

  @Test
  func testResponseConnectivityAndValueContracts() {
    let url = URL(string: "https://example.test/status")!
    let statuses = [
      (99, false, false, false, false, false),
      (100, true, false, false, false, false),
      (204, false, true, false, false, false),
      (302, false, false, true, false, false),
      (404, false, false, false, true, false),
      (503, false, false, false, false, true)
    ]
    for (status, informational, success, redirect, client, server) in statuses {
      let response = SwiftUIWebNetworking.HTTPURLResponse(url: url, statusCode: status, headerFields: ["X-Test": "ok"])
      _expectEqual(response.isInformational, informational)
      _expectEqual(response.isSuccess, success)
      _expectEqual(response.isRedirection, redirect)
      _expectEqual(response.isClientError, client)
      _expectEqual(response.isServerError, server)
      _expectEqual(response.value(forHTTPHeaderField: "x-test"), "ok")
    }
    let convenience = SwiftUIWebNetworking.HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/3")
    _expectEqual(convenience!.httpVersion, "HTTP/3")
    _expectNil(convenience!.value(forHTTPHeaderField: "missing"))
    let base = URLResponse(url: url, mimeType: "text/plain", textEncodingName: "utf-8")
    _expectEqual(base.mimeType, "text/plain")
    _expectEqual(base.textEncodingName, "utf-8")

    let unknown = NetworkConnectivityState(status: .unknown)
    _expectEqual(unknown.pathStatus, .unknown)
    _expectNil(unknown.isOnline)
    let offline = NetworkConnectivityState(status: .offline, isExpensive: false, isConstrained: true)
    _expectEqual(offline.pathStatus, .unsatisfied)
    _expectEqual(offline.isOnline, false)
    _expectFalse(offline == NetworkConnectivityState(status: .online))
    let close = WebSocketCloseInfo(code: 1001, reason: Data("bye".utf8), wasClean: true)
    _expectEqual(close.reasonString, "bye")
    _expectEqual(WebSocketCloseInfo(code: 1000).reasonString, nil)
    _expectEqual(NetworkError.unavailable.description, "Networking is not available on this host")
    _expectEqual(NetworkError.invalidRequest("bad").description, "bad")
    _expectEqual(NetworkError.forbiddenHeader("Cookie").description, "The browser forbids the HTTP header 'Cookie'")
    _expectEqual(NetworkError.unsupported("nope").description, "nope")
    _expectEqual(NetworkError.transport("down").description, "down")
    _expectEqual(NetworkError.webSocketClosed(code: 1006, reason: nil).description, "WebSocket closed (1006)")
    _expectEqual(NetworkError.webSocketClosed(code: 1000, reason: "bye").description, "WebSocket closed (1000): bye")
  }

  @Test
  func testNativeStreamingUploadDownloadAndTaskLifecycle() async throws {
    NetworkRuntime.installConfigured { request, _ in
      _expectEqual(request.effectiveHTTPMethod, "POST")
      if request.httpBody != nil {
        _expectEqual(request.httpBody?.utf8String(), "upload")
      }
      return (
        Data("response".utf8),
        SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 201, headerFields: ["content-length": "8"], expectedContentLength: 8)
      )
    }
    keepOnlyTheRequestTransport()
    let session = URLSession(configuration: URLSessionConfiguration(timeoutIntervalForRequest: 1))
    var request = URLRequest(url: URL(string: "https://example.test/upload")!)
    request.method = .post
    let (uploaded, uploadResponse) = try await session.upload(
      for: request,
      from: Data("upload".utf8)
    )
    _expectEqual(uploaded.utf8String(), "response")
    _expectEqual((uploadResponse as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 201)

    let expectation = _makeExpectation()
    let task = session.dataTask(with: request) { data, response, error in
      _expectNil(error)
      _expectEqual(data?.utf8String(), "response")
      _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 201)
      expectation.fulfill()
    }
    task.resume()
    await _fulfillment(of: [expectation], timeout: 1)
    _expectEqual(task.state, SwiftUIWebNetworking.URLSessionTask.State.completed)
    _expectEqual(task.countOfBytesReceived, 8)
    _expectEqual((task.response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 201)

    NetworkRuntime.installStreaming { request, _ in
      let source = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data("a".utf8))
        continuation.yield(Data("bc".utf8))
        continuation.finish()
      }
      return (SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 200, expectedContentLength: 3), source)
    }
    NetworkRuntime.installDownloadMaterializer { data, response in
      _expectEqual(data.utf8String(), "abc")
      return URL(string: "blob://downloaded")
    }
    let (downloadURL, downloadResponse) = try await session.download(from: URL(string: "https://example.test/file")!)
    _expectEqual(downloadURL.absoluteString, "blob://downloaded")
    _expectEqual((downloadResponse as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
  }

  @Test
  func testFallbackStreamingUploadsAndDownloadTasks() async throws {
    NetworkRuntime.install(nil)
    NetworkRuntime.installStreaming(nil)
    NetworkRuntime.installDownloadMaterializer(nil)
    NetworkRuntime.installConfigured { request, _ in
      if request.httpBody != nil { _expectEqual(request.httpBody?.utf8String(), "streamed") }
      return (
        Data("ok".utf8),
        SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 200, expectedContentLength: 2)
      )
    }
    keepOnlyTheRequestTransport()
    let session = SwiftUIWebNetworking.URLSession(configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0))
    let source = AsyncThrowingStream<Data, Error> { continuation in
      continuation.yield(Data("stream".utf8))
      continuation.yield(Data("ed".utf8))
      continuation.finish()
    }
    var uploadRequest = URLRequest(url: URL(string: "https://example.test/stream-upload")!)
    uploadRequest.method = .post
    let (data, response) = try await session.upload(
      for: uploadRequest,
      from: source
    )
    _expectEqual(data.utf8String(), "ok")
    _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)

    // With no streaming adapter, bytes() exposes the configured response as a
    // one-element stream and download() falls back to the response URL.
    let (bytes, bytesResponse) = try await session.bytes(
      for: URLRequest(url: URL(string: "https://example.test/fallback")!)
    )
    var body = Data()
    for try await chunk in bytes { body.append(contentsOf: chunk) }
    _expectEqual(body.utf8String(), "ok")
    _expectEqual((bytesResponse as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
    let (downloadURL, _) = try await session.download(from: URL(string: "https://example.test/fallback")!)
    _expectEqual(downloadURL.absoluteString, "https://example.test/fallback")

    let uploadExpectation = _makeExpectation()
    var taskRequest = URLRequest(url: URL(string: "https://example.test/task")!)
    taskRequest.method = .post
    let uploadTask = session.uploadTask(
      with: taskRequest,
      from: Data("streamed".utf8),
      completionHandler: { data, response, error in
        _expectNil(error)
        _expectEqual(data?.utf8String(), "ok")
        _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
        uploadExpectation.fulfill()
      }
    )
    uploadTask.resume()
    await _fulfillment(of: [uploadExpectation], timeout: 1)

    let downloadExpectation = _makeExpectation()
    let downloadTask = session.downloadTask(
      with: URL(string: "https://example.test/task-download")!,
      completionHandler: { url, response, error in
        _expectNil(error)
        _expectEqual(url?.absoluteString, "https://example.test/task-download")
        _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 200)
        downloadExpectation.fulfill()
      }
    )
    downloadTask.resume()
    await _fulfillment(of: [downloadExpectation], timeout: 1)
  }

  @Test
  func testDownloadTaskReportsTransportFailureToCompletionHandler() async {
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installStreaming { _, _ in
      throw NetworkError.transport("download source failed")
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    let expectation = _makeExpectation()
    let task = session.downloadTask(
      with: URL(string: "https://example.test/download-failure")!
    ) { url, response, error in
      _expectNil(url)
      _expectNil(response)
      _expectEqual((error as? SwiftUIWebNetworking.URLError)?.code, .unknown)
      expectation.fulfill()
    }
    task.resume()
    await _fulfillment(of: [expectation], timeout: 1)
  }

  @Test
  func testRuntimeAvailabilityAndTaskLifecycle() async throws {
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installStreaming { request, _ in
      let stream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.finish()
      }
      return (SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 200), stream)
    }
    _expectTrue(NetworkRuntime.isAvailable)
    NetworkRuntime.installStreaming(nil)
    _expectFalse(NetworkRuntime.isAvailable)

    NetworkRuntime.installConfigured { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return (Data(), SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    let session = SwiftUIWebNetworking.URLSession(configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0))
    let task = session.dataTask(with: URL(string: "https://example.test/lifecycle")!) { _, _, error in
      _expectTrue(error is SwiftUIWebNetworking.URLError)
    }
    _expectEqual(task.state, .suspended)
    _expectNotNil(task.currentRequest)
    task.resume()
    task.resume()
    _expectEqual(task.state, .running)
    task.suspend()
    _expectEqual(task.state, .suspended)
    task.resume()
    task.cancel()
    _expectEqual(task.state, .canceling)
    task.cancel()
  }

  @Test
  func testWebSocketCallbacksAndUnsupportedLifecycle() async throws {
    NetworkRuntime.installWebSocket { request, _ in
      _expectEqual(request.url!.absoluteString, "wss://example.test/callback")
      return WebSocketConnection(
        send: { _ in },
        receive: { .data(Data("frame".utf8)) },
        close: { _, _ in },
        ping: {},
        state: { .open },
        closeInfo: { WebSocketCloseInfo(code: 1000, wasClean: true) }
      )
    }
    let session = SwiftUIWebNetworking.URLSession.shared
    let suspendedTask = session.webSocketTask(
      with: URL(string: "wss://example.test/suspended")!,
      protocols: ["chat", "superchat"]
    )
    _expectEqual(suspendedTask.originalRequest!.webSocketProtocols, ["chat", "superchat"])
    _expectEqual(suspendedTask.webSocketState, .closed)
    _expectEqual(suspendedTask.closeCode, .invalid)
    _expectNil(suspendedTask.closeReason)
    _expectNil(suspendedTask.closeInfo)
    _expectNil(suspendedTask.negotiatedProtocol)
    do {
      _ = try await suspendedTask.receive()
      _fail("A suspended socket must not receive")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unsupportedURL)
    }
    do {
      try await suspendedTask.sendPing()
      _fail("A suspended socket must not ping")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unsupportedURL)
    }
    suspendedTask.cancel(with: .goingAway, reason: Data("going away".utf8))
    _expectEqual(suspendedTask.webSocketState, .closing)
    suspendedTask.cancel(
      with: SwiftUIWebNetworking.URLSessionWebSocketTask.CloseCode.goingAway,
      reason: Data("again".utf8)
    )
    do {
      _ = try await suspendedTask.receive()
      _fail("A cancelled socket must not receive")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    }
    let cancelledSendExpectation = _makeExpectation()
    suspendedTask.send(.string("cancelled")) { error in
      _expectEqual((error as? SwiftUIWebNetworking.URLError)?.code, .cancelled)
      cancelledSendExpectation.fulfill()
    }
    await _fulfillment(of: [cancelledSendExpectation], timeout: 1)
    let cancelledReceiveExpectation = _makeExpectation()
    suspendedTask.receive { result in
      if case .failure(let error) = result {
        _expectEqual((error as? SwiftUIWebNetworking.URLError)?.code, .cancelled)
      } else {
        _fail("A cancelled socket callback must report failure")
      }
      cancelledReceiveExpectation.fulfill()
    }
    await _fulfillment(of: [cancelledReceiveExpectation], timeout: 1)
    let cancelledPingExpectation = _makeExpectation()
    suspendedTask.sendPing { error in
      _expectEqual((error as? SwiftUIWebNetworking.URLError)?.code, .cancelled)
      cancelledPingExpectation.fulfill()
    }
    await _fulfillment(of: [cancelledPingExpectation], timeout: 1)

    let task = session.webSocketTask(with: URL(string: "wss://example.test/callback")!)
    do {
      try await task.send(.string("before-resume"))
      _fail("A suspended socket must not send")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unsupportedURL)
    }
    task.resume()
    try await task.send(.data(Data("ping".utf8)))
    let received = try await task.receive()
    _expectEqual(received, SwiftUIWebNetworking.URLSessionWebSocketTask.Message.data(Data("frame".utf8)))
    let sendExpectation = _makeExpectation()
    task.send(.string("callback")) { error in
      _expectNil(error)
      sendExpectation.fulfill()
    }
    await _fulfillment(of: [sendExpectation], timeout: 1)
    let receiveExpectation = _makeExpectation()
    task.receive { result in
      if case .success(.data(let value)) = result { _expectEqual(value.utf8String(), "frame") }
      else { _fail("Expected a data frame") }
      receiveExpectation.fulfill()
    }
    await _fulfillment(of: [receiveExpectation], timeout: 1)
    let pingExpectation = _makeExpectation()
    task.sendPing { error in
      _expectNil(error)
      pingExpectation.fulfill()
    }
    await _fulfillment(of: [pingExpectation], timeout: 1)
    _expectEqual(task.closeCode, SwiftUIWebNetworking.URLSessionWebSocketTask.CloseCode.normalClosure)
    _expectEqual(task.webSocketState, SwiftUIWebNetworking.WebSocketConnectionState.open)
    _expectEqual(task.closeInfo?.code, 1000)
    _expectNil(task.closeReason)
    _expectNil(task.negotiatedProtocol)
    task.cancel()
    _expectEqual(task.webSocketState, SwiftUIWebNetworking.WebSocketConnectionState.open)
    do {
      try await task.send(.string("after-cancel"))
      _fail("A cancelled socket must not send")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .cancelled)
    }
    NetworkRuntime.installWebSocket(nil)
  }

  @Test
  func testWebSocketConnectingStateAndUnsupportedPingCapability() async throws {
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    NetworkRuntime.installWebSocket { request, _ in
      try await Task.sleep(nanoseconds: 30_000_000_000)
      return WebSocketConnection(
        send: { _ in },
        receive: { .string("unused") },
        close: { _, _ in },
        state: { .open }
      )
    }
    let connecting = session.webSocketTask(with: URL(string: "wss://example.test/connecting")!)
    connecting.resume()
    await Task.yield()
    _expectEqual(connecting.webSocketState, .connecting)
    connecting.cancel()
    _expectEqual(connecting.webSocketState, .closing)

    NetworkRuntime.installWebSocket { _, _ in
      WebSocketConnection(
        send: { _ in },
        receive: { .string("ready") },
        close: { _, _ in },
        state: { .open }
      )
    }
    let noPing = session.webSocketTask(with: URL(string: "wss://example.test/no-ping")!)
    noPing.resume()
    try await noPing.send(.string("connect"))
    _expectEqual(noPing.webSocketState, .open)
    do {
      try await noPing.sendPing()
      _fail("A host without ping support must report the capability gap")
    } catch let error as SwiftUIWebNetworking.URLError {
      _expectEqual(error.code, .unsupportedURL)
      _expectEqual(error.reason, "WebSocket control-frame ping is unavailable in browsers")
    }
    noPing.cancel()
  }

  @Test
  func testWebSocketDefaultMetadataAndInvalidCloseCodeFallback() async throws {
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(
        timeoutIntervalForRequest: 0,
        timeoutIntervalForResource: 0
      )
    )
    NetworkRuntime.installWebSocket { request, _ in
      let closeInfo: WebSocketConnection.CloseInfo?
      if request.url!.absoluteString.hasSuffix("/invalid-close") {
        closeInfo = { WebSocketCloseInfo(code: Int.max) }
      } else {
        closeInfo = nil
      }
      return WebSocketConnection(
        send: { _ in },
        receive: { .string("ready") },
        close: { _, _ in },
        closeInfo: closeInfo
      )
    }

    let defaults = session.webSocketTask(
      with: URL(string: "wss://example.test/default-metadata")!
    )
    defaults.resume()
    try await defaults.send(.string("resolve"))
    _expectEqual(defaults.webSocketState, .open)
    _expectEqual(defaults.closeCode, .invalid)
    _expectNil(defaults.closeInfo)
    _expectNil(defaults.closeReason)
    defaults.cancel()

    let invalid = session.webSocketTask(
      with: URL(string: "wss://example.test/invalid-close")!
    )
    invalid.resume()
    try await invalid.send(.string("resolve"))
    _expectEqual(invalid.closeInfo?.code, Int.max)
    _expectEqual(invalid.closeCode, .invalid)
    invalid.cancel()
  }

  private struct UploadProgressEvent: Sendable {
    let bytesSent: Int64
    let totalSent: Int64
    let totalExpected: Int64
  }

  /// Records what a URLSessionTaskDelegate hears about upload progress.
  private final class UploadProgressRecorder: SwiftUIWebNetworking.URLSessionTaskDelegate, @unchecked Sendable {
    private(set) var events: [UploadProgressEvent] = []

    func urlSession(
      _ session: SwiftUIWebNetworking.URLSession,
      task: SwiftUIWebNetworking.URLSessionTask,
      didSendBodyData bytesSent: Int64,
      totalBytesSent: Int64,
      totalBytesExpectedToSend: Int64
    ) {
      events.append(UploadProgressEvent(bytesSent: bytesSent, totalSent: totalBytesSent, totalExpected: totalBytesExpectedToSend))
    }
  }

  private final class UploadProgressValues: @unchecked Sendable {
    private(set) var values: [(Int64, Int64)] = []
    func record(_ sent: Int64, _ total: Int64) { values.append((sent, total)) }
  }

  @Test
  func testUploadProgressReachesTheDelegateFromTheProgressTransport() async throws {
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.upload?(2, 6)
      progress.upload?(2, 6)
      progress.upload?(6, 6)
      return (Data(), SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 204))
    }
    defer { NetworkRuntime.installTransferProgress(nil) }
    // A configured transport keeps URLSession from installing the native adapter, which would replace
    // the upload-progress transport this test installs.
    NetworkRuntime.installConfigured { _, _ in throw NetworkError.unavailable }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0)
    )
    let delegate = UploadProgressRecorder()
    var request = URLRequest(url: URL(string: "https://example.test/upload")!)
    request.httpMethod = "POST"
    let (_, response) = try await session.upload(for: request, from: Data("abcdef".utf8), delegate: delegate)
    _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 204)
    // Foundation reports the increase since the previous callback; a repeated count reports nothing.
    _expectEqual(delegate.events.map { $0.bytesSent }, [2, 4])
    _expectEqual(delegate.events.map { $0.totalSent }, [2, 6])
    _expectEqual(delegate.events.map { $0.totalExpected }, [6, 6])
  }

  @Test
  func testUploadProgressWithoutATransportIsReportedOnceWhenTheRequestCompletes() async throws {
    NetworkRuntime.install(nil)
    NetworkRuntime.installTransferProgress(nil)
    NetworkRuntime.installConfigured { request, _ in
      (Data(), SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 200))
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0)
    )
    let delegate = UploadProgressRecorder()
    _ = try await session.data(
      for: URLRequest(url: URL(string: "https://example.test/fallback")!),
      delegate: delegate
    )
    // No body, so no callback.
    _expectEqual(delegate.events.count, 0)

    var postRequest = URLRequest(url: URL(string: "https://example.test/fallback")!)
    postRequest.httpMethod = "POST"
    _ = try await session.upload(
      for: postRequest,
      from: Data("abcdef".utf8),
      delegate: delegate
    )
    _expectEqual(delegate.events.map { $0.bytesSent }, [6])
    _expectEqual(delegate.events.map { $0.totalSent }, [6])
    _expectEqual(delegate.events.map { $0.totalExpected }, [6])
  }

  @Test
  func testStreamedRequestWithBodyReportsItsUploadWhenHeadersArrive() async throws {
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installTransferProgress(nil)
    NetworkRuntime.installStreaming { request, _ in
      let stream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data("ok".utf8))
        continuation.finish()
      }
      return (SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 200), stream)
    }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0)
    )
    let delegate = UploadProgressRecorder()
    var request = URLRequest(url: URL(string: "https://example.test/stream-upload")!)
    request.httpMethod = "PUT"
    request.httpBody = Data("12345".utf8)
    let (stream, _) = try await session.bytes(for: request, delegate: delegate)
    _expectEqual(delegate.events.map { $0.totalSent }, [5])
    var received = Data()
    for try await chunk in stream { received.append(contentsOf: chunk) }
    _expectEqual(received, Data("ok".utf8))
  }

  @Test
  func testCompletionHandlerUploadTaskHearsNoUploadCallbackFromItsDelegate() async {
    // Foundation calls no task-level delegate method for a task created with a completion handler (probed against
    // Foundation: the task delegate hears nothing, while the counters and the handler still run).
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.upload?(3, 3)
      return (Data("done".utf8), SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 201))
    }
    defer { NetworkRuntime.installTransferProgress(nil) }
    // A configured transport keeps URLSession from installing the native adapter, which would replace
    // the upload-progress transport this test installs.
    NetworkRuntime.installConfigured { _, _ in throw NetworkError.unavailable }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0)
    )
    let delegate = UploadProgressRecorder()
    let expectation = _makeExpectation()
    var taskRequest = URLRequest(url: URL(string: "https://example.test/task-upload")!)
    taskRequest.httpMethod = "POST"
    let task = session.uploadTask(
      with: taskRequest,
      from: Data("abc".utf8)
    ) { data, response, error in
      _expectNil(error)
      _expectEqual(data, Data("done".utf8))
      _expectEqual((response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 201)
      expectation.fulfill()
    }
    task.delegate = delegate
    task.resume()
    await _fulfillment(of: [expectation], timeout: 1)
    _expectEqual(delegate.events.count, 0)
    _expectEqual(task.countOfBytesSent, 3)
    _expectEqual(task.countOfBytesExpectedToSend, 3)
  }

  @Test
  func testDelegateBasedUploadTaskReportsUploadAndCompletion() async {
    // A task created without a completion handler is the one a delegate hears: upload progress, then completion.
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured(nil)
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.upload?(3, 3)
      return (Data("done".utf8), SwiftUIWebNetworking.HTTPURLResponse(url: request.url!, statusCode: 201))
    }
    defer { NetworkRuntime.installTransferProgress(nil) }
    NetworkRuntime.installConfigured { _, _ in throw NetworkError.unavailable }
    let session = SwiftUIWebNetworking.URLSession(
      configuration: SwiftUIWebNetworking.URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0)
    )
    let delegate = UploadProgressRecorder()
    var taskRequest = URLRequest(url: URL(string: "https://example.test/delegate-upload")!)
    taskRequest.httpMethod = "POST"
    let task = session.uploadTask(with: taskRequest, from: Data("abc".utf8))
    task.delegate = delegate
    task.resume()
    while task.state != .completed {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    _expectEqual(delegate.events.map { $0.totalSent }, [3])
    _expectEqual(task.countOfBytesSent, 3)
    _expectEqual((task.response as? SwiftUIWebNetworking.HTTPURLResponse)?.statusCode, 201)
  }

  @Test
  func testWebCredentialsPolicyFeedsTheBrowserRequestAndDefaultsToSameOrigin() {
    var configuration = SwiftUIWebNetworking.URLSessionConfiguration.default
    let url = URL(string: "https://example.test/credentials")!
    var request = URLRequest(url: url)
    _expectEqual(configuration.webCredentialsPolicy, WebCredentialsPolicy.sameOrigin)
    _expectEqual(configuration.credentialsPolicy(for: request), .sameOrigin)

    configuration.webCredentialsPolicy = .include
    _expectEqual(configuration.credentialsPolicy(for: request), .include)

    request.webCredentialsPolicy = .omit
    _expectEqual(request.webCredentialsPolicy, WebCredentialsPolicy.omit)
    _expectEqual(configuration.credentialsPolicy(for: request), .omit)

    request.webCredentialsPolicy = nil
    _expectEqual(configuration.credentialsPolicy(for: request), .include)

    // The cookie switches still win over either policy.
    request.httpShouldHandleCookies = false
    _expectEqual(configuration.credentialsPolicy(for: request), .omit)
    request.httpShouldHandleCookies = true
    configuration.httpShouldSetCookies = false
    _expectEqual(configuration.credentialsPolicy(for: request), .omit)
  }

  @Test
  func testURLErrorCodesKeepFoundationRawValuesAndMapEveryHostFailure() {
    _expectEqual(SwiftUIWebNetworking.URLError.Code.unknown.rawValue, -1)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.cancelled.rawValue, -999)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.badURL.rawValue, -1000)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.timedOut.rawValue, -1001)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.notConnectedToInternet.rawValue, -1009)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.appTransportSecurityRequiresSecureConnection.rawValue, -1022)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.dataLengthExceedsMaximum.rawValue, -1103)
    _expectEqual(SwiftUIWebNetworking.URLError.Code.backgroundSessionWasDisconnected.rawValue, -997)
    _expectEqual(SwiftUIWebNetworking.URLError(.timedOut).errorCode, -1001)

    let cases: [(NetworkError, SwiftUIWebNetworking.URLError.Code)] = [
      (.unavailable, .resourceUnavailable),
      (.invalidRequest("bad"), .unknown),
      (.badURL("bad"), .badURL),
      (.forbiddenHeader("Cookie"), .unknown),
      (.unsupported("nope"), .unsupportedURL),
      (.webSocketClosed(code: 1006, reason: nil), .networkConnectionLost),
      (.transport("down"), .unknown),
      (.cancelled, .cancelled),
      (.timedOut, .timedOut),
      (.connectionFailed("dns"), .cannotConnectToHost),
      (.offline("offline"), .notConnectedToInternet),
      (.connectionLost("reset"), .networkConnectionLost),
      (.responseTooLarge("big"), .dataLengthExceedsMaximum),
      (.insecureRequest("mixed"), .appTransportSecurityRequiresSecureConnection),
    ]
    for (error, code) in cases {
      _expectEqual(_urlErrorCode(error), code)
      _expectEqual(_urlError(error).code, code)
    }
    _expectEqual(_urlError(CancellationError()).code, .cancelled)
    _expectEqual(_urlError(SwiftUIWebNetworking.URLError(.timedOut)).code, .timedOut)
    _expectEqual(_urlError(NetworkError.transport("x")).reason, "x")

    let url = URL(string: "https://example.test/a")!
    let failed = _urlError(NetworkError.connectionFailed("dns"), failingURL: url)
    _expectEqual(failed.failingURL, url)
    _expectEqual(failed.failureURLString, "https://example.test/a")
    _expectEqual(failed.reason, "dns")
  }
}
#endif
