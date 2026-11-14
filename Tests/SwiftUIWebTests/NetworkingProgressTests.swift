#if !os(WASI)
import Foundation
import Testing
@testable import SwiftUIWebNetworking
@_spi(Renderer) import SwiftUIWebLocking

/// A body that yields the given chunks. A free function, so transport closures capture nothing: the hook that holds
/// them is released while it is being replaced, and a captured test instance would deinitialize inside that lock.
private func streamedChunks(_ chunks: [String]) -> AsyncThrowingStream<Data, Error> {
  AsyncThrowingStream { continuation in
    for chunk in chunks { continuation.yield(Data(chunk.utf8)) }
    continuation.finish()
  }
}

/// Removes the hosts the suite's tests install (see `ProcessGlobalStateTrait.tearDown`).
@MainActor private func resetProgressHosts() {
  NetworkRuntime.install(nil)
  NetworkRuntime.installConfigured(nil)
  NetworkRuntime.installStreaming(nil)
  NetworkRuntime.installTransferProgress(nil)
  NetworkRuntime.installDownloadMaterializer(nil)
}

/// Receive-side progress and delegate callbacks, driven by fake transports. Each transport reports the counts a
/// host reports (buffered progress, or streamed chunks), so the task's counters, `progress` and the delegate calls
/// are checked without a network.
@Suite(.serialized, .processGlobalState(tearDown: resetProgressHosts))
@MainActor
final class NetworkingProgressTests {
  private struct Write: Equatable, Sendable {
    let bytes: Int64
    let totalWritten: Int64
    let expected: Int64
  }

  /// Records what a delegate hears. Foundation calls delegates on its own queues, so state is locked.
  private final class Recorder: URLSessionDownloadDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = _RuntimeLock()
    private(set) var writes: [Write] = []
    private(set) var chunks: [Int] = []
    private(set) var finishedLocations: [URL] = []
    private(set) var completions: [(any Error)?] = []
    /// `progress` as read inside each `didWriteData`: completed units and fraction.
    private(set) var writeProgress: [(completed: Int64, fraction: Double)] = []

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
      let write = Write(bytes: bytesWritten, totalWritten: totalBytesWritten, expected: totalBytesExpectedToWrite)
      let sample = (completed: downloadTask.progress.completedUnitCount, fraction: downloadTask.progress.fractionCompleted)
      lock.withLock {
        writes.append(write)
        writeProgress.append(sample)
      }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
      lock.withLock { finishedLocations.append(location) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
      let count = data.count
      lock.withLock { chunks.append(count) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
      lock.withLock { completions.append(error) }
    }
  }

  private func makeSession() -> URLSession {
    URLSession(configuration: URLSessionConfiguration(timeoutIntervalForRequest: 0, timeoutIntervalForResource: 0))
  }

  /// Installs fallbacks so that no request reaches a real network; a test replaces the transport it exercises.
  private func installFallbacks() {
    NetworkRuntime.install(nil)
    NetworkRuntime.installConfigured { request, _ in (Data(), HTTPURLResponse(url: request.url!, statusCode: 500)) }
    NetworkRuntime.installStreaming { request, _ in
      (HTTPURLResponse(url: request.url!, statusCode: 500), AsyncThrowingStream { $0.finish() })
    }
    NetworkRuntime.installTransferProgress(nil)
    NetworkRuntime.installDownloadMaterializer(nil)
  }

  /// Resumes a task and waits for it to finish, so its counters and callbacks are final when the test reads them.
  private func run(_ task: URLSessionTask) async {
    task.resume()
    while task.state != .completed {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  @Test
  func testBufferedDataTaskReportsItsDownloadProgressAndTheFinalCounts() async throws {
    installFallbacks()
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.download?(0, 10)
      progress.download?(4, 10)
      progress.download?(10, 10)
      return (Data("0123456789".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: [:], expectedContentLength: 10))
    }
    let task = makeSession().dataTask(with: URL(string: "https://progress.test/buffered")!) { _, _, _ in }
    await run(task)

    _expectEqual(task.countOfBytesReceived, 10)
    _expectEqual(task.countOfBytesExpectedToReceive, 10)
    // Foundation's model: 100 units, complete when the task finishes.
    _expectEqual(task.progress.totalUnitCount, 100)
    _expectEqual(task.progress.completedUnitCount, 100)
    _expectEqual(task.progress.fractionCompleted, 1)
  }

  @Test
  func testAnUnknownLengthIsReportedAsMinusOneWithoutAFraction() async throws {
    installFallbacks()
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.download?(3, -1)
      return (Data("abc".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: [:], expectedContentLength: -1))
    }
    let task = makeSession().dataTask(with: URL(string: "https://progress.test/unknown")!) { _, _, _ in }
    await run(task)

    _expectEqual(task.countOfBytesReceived, 3)
    _expectEqual(task.countOfBytesExpectedToReceive, -1)
    // The unknown body share never adds to the fraction, so only the completed response step remains until the end.
    _expectEqual(task.progress.totalUnitCount, 100)
    _expectEqual(task.progress.completedUnitCount, 100)
  }

  @Test
  func testReceivingPastTheHeaderLengthMakesTheTotalUnknown() async throws {
    // A compressed body is counted after decoding, so its header length can be passed. The total is then unknown.
    installFallbacks()
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.download?(12, 5)
      return (Data(count: 12), HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: [:], expectedContentLength: 5))
    }
    let task = makeSession().dataTask(with: URL(string: "https://progress.test/overrun")!) { _, _, _ in }
    await run(task)

    _expectEqual(task.countOfBytesReceived, 12)
    _expectEqual(task.countOfBytesExpectedToReceive, -1)
    _expectEqual(task.progress.totalUnitCount, 100)
  }

  @Test
  func testDownloadTaskStreamsEachChunkToItsDelegateWithFoundationCounts() async throws {
    installFallbacks()
    NetworkRuntime.installStreaming { request, _ in
      (HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: ["content-length": "9"], expectedContentLength: 9),
       streamedChunks(["abc", "defg", "hi"]))
    }
    let recorder = Recorder()
    let task = makeSession().downloadTask(with: URL(string: "https://progress.test/download")!)
    task.delegate = recorder
    await run(task)

    _expectEqual(recorder.writes, [
      Write(bytes: 3, totalWritten: 3, expected: 9),
      Write(bytes: 4, totalWritten: 7, expected: 9),
      Write(bytes: 2, totalWritten: 9, expected: 9),
    ])
    _expectEqual(recorder.finishedLocations, [URL(string: "https://progress.test/download")!])
    _expectEqual(recorder.completions.count, 1)
    _expectNil(recorder.completions.first ?? nil)
    _expectEqual(task.countOfBytesReceived, 9)
    // Each write, as Foundation reports it: 5 units done after the response, the body's share by bytes, and all 100
    // once the last byte arrives (the body is then complete).
    _expectEqual(recorder.writeProgress.map { $0.completed }, [5, 5, 100])
    _expectEqual(recorder.writeProgress[0].fraction, 0.05 + 0.95 * 3 / 9, accuracy: 1e-9)
    _expectEqual(recorder.writeProgress[1].fraction, 0.05 + 0.95 * 7 / 9, accuracy: 1e-9)
    _expectEqual(recorder.writeProgress[2].fraction, 1, accuracy: 1e-9)
    _expectEqual(task.progress.totalUnitCount, 100)
    _expectEqual(task.progress.completedUnitCount, 100)
  }

  @Test
  func testDataTaskDelegateHearsEachStreamedChunkAsItArrives() async throws {
    installFallbacks()
    NetworkRuntime.installStreaming { request, _ in
      (HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: [:], expectedContentLength: -1),
       streamedChunks(["one", "three"]))
    }
    let recorder = Recorder()
    let task = makeSession().dataTask(with: URL(string: "https://progress.test/chunked")!)
    task.delegate = recorder
    await run(task)

    _expectEqual(recorder.chunks, [3, 5])
    // A data task never reaches the download callbacks.
    _expectEqual(recorder.writes.count, 0)
    _expectEqual(recorder.finishedLocations.count, 0)
    _expectEqual(recorder.completions.count, 1)
    _expectNil(recorder.completions.first ?? nil)
  }

  @Test
  func testDelegateTaskReportsItsFailureToDidCompleteWithError() async throws {
    installFallbacks()
    NetworkRuntime.installStreaming { _, _ in throw NetworkError.unavailable }
    let recorder = Recorder()
    let task = makeSession().dataTask(with: URL(string: "https://progress.test/refused")!)
    task.delegate = recorder
    await run(task)

    _expectEqual(recorder.chunks, [])
    _expectEqual(recorder.completions.count, 1)
    _expectEqual((recorder.completions.first ?? nil) == nil, false)
  }

  @Test
  func testCompletionHandlerTaskHearsNoReceiveCallbacks() async throws {
    // Foundation ignores a task's delegate for a task created with a completion handler: the handler is the only
    // receiver, but the counters still update.
    installFallbacks()
    // The handler's task is buffered (no chunk callbacks to deliver), so the body comes from the configured transport.
    NetworkRuntime.installConfigured { request, _ in
      (Data("12345678".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: [:], expectedContentLength: 8))
    }
    let recorder = Recorder()
    let (data, error): (Data?, (any Error)?) = await withCheckedContinuation { continuation in
      let task = makeSession().dataTask(with: URL(string: "https://progress.test/handler")!) { data, _, error in
        continuation.resume(returning: (data, error))
      }
      task.delegate = recorder
      task.resume()
    }
    _expectNil(error)
    _expectEqual(data, Data("12345678".utf8))
    _expectEqual(recorder.chunks, [])
    _expectEqual(recorder.completions.count, 0)
  }

  @Test
  func testBufferedBodyWithADataDelegateReportsItsUploadWithoutChunkCallbacks() async throws {
    installFallbacks()
    NetworkRuntime.installTransferProgress { request, _, progress in
      progress.upload?(2, 4)
      progress.upload?(4, 4)
      return (Data("reply".utf8), HTTPURLResponse(url: request.url!, statusCode: 201, headerFields: [:], expectedContentLength: 5))
    }
    var request = URLRequest(url: URL(string: "https://progress.test/upload")!)
    request.httpMethod = "POST"
    request.httpBody = Data("body".utf8)
    let recorder = Recorder()
    let (data, response) = try await makeSession().data(for: request, delegate: recorder)
    _expectEqual(data, Data("reply".utf8))
    _expectEqual((response as? HTTPURLResponse)?.statusCode, 201)
    // The async API hears no receive callbacks, as Foundation's does not.
    _expectEqual(recorder.chunks, [])
  }

  @Test
  func testAsyncDownloadWithADelegateReportsNoDownloadCallbacks() async throws {
    // Foundation's async `download(for:delegate:)` calls only task-level delegate methods. The chunk and finish
    // callbacks belong to tasks created with `downloadTask(with:)`.
    installFallbacks()
    NetworkRuntime.installStreaming { request, _ in
      (HTTPURLResponse(url: request.url!, statusCode: 200, headerFields: ["content-length": "4"], expectedContentLength: 4),
       streamedChunks(["ab", "cd"]))
    }
    let recorder = Recorder()
    let (location, response) = try await makeSession().download(
      for: URLRequest(url: URL(string: "https://progress.test/async-download")!),
      delegate: recorder
    )
    _expectEqual((response as? HTTPURLResponse)?.statusCode, 200)
    _expectEqual(location.absoluteString, "https://progress.test/async-download")
    _expectEqual(recorder.writes.count, 0)
    _expectEqual(recorder.finishedLocations.count, 0)
  }

  @Test
  func testExpectedContentLengthFollowsFoundationsHeaderRule() {
    _expectEqual(_expectedContentLength(headers: [:]), -1)
    _expectEqual(_expectedContentLength(headers: ["Content-Length": "12"]), 12)
    _expectEqual(_expectedContentLength(headers: ["content-length": "12", "Content-Encoding": "gzip"]), -1)
    _expectEqual(_expectedContentLength(headers: ["content-length": "12", "content-encoding": "identity"]), 12)
    _expectEqual(_expectedContentLength(headers: ["content-length": "12", "content-encoding": ""]), 12)
    _expectEqual(_expectedContentLength(headers: ["content-length": "not-a-number"]), -1)
  }
}
#endif
