import Testing
@testable import SwiftUIWebBrowserIO
@_spi(Renderer) import SwiftUIWebLocking
import CSwiftUIWebBrowserIO

/// Contract tests for the BrowserIO wire format, response routing and the
/// native (host-less) behaviour of every public BrowserIO entry point.
///
/// Native builds link the C adapter's host stubs: asynchronous requests fail
/// synchronously with -7 and synchronous requests return no result handle. The
/// tests therefore pin the failure surface callers rely on, and drive the
/// response router and packet reader directly with host-shaped bytes.
/// Runs `body` and returns the BrowserIO error code it threw, `nil` on success
/// and 1 for any other error.
@MainActor
private func browserIOErrorCode(_ body: @MainActor () async throws -> Void) async -> Int32? {
  do {
    try await body()
    return nil
  } catch let error as BrowserIOError {
    return error.code
  } catch {
    return 1
  }
}

@Suite(.processGlobalState)
@MainActor
final class BrowserIOContractTests {
  // MARK: - C adapter

  @Test
  func nativeCAdapterExposesClocksEnvironmentAndExecutorHooks() {
    _swiftUIWebInstallMainExecutorGetter(nil, checkIsolated: nil, isIsolating: nil, isOnExecutor: nil, isMainExecutor: nil)
    _swiftUIWebInstallConcurrencyHooks(nil, nil, nil)
    // Off the browser there is no event loop to wake; the call must be a no-op.
    browser_io_wake_executor()

    #expect(browser_io_environment_value(nil) == nil)
    #expect(browser_io_environment_value("SWIFTUIWEB_BROWSER_IO_TEST_UNSET_VARIABLE") == nil)
    let path = browser_io_environment_value("PATH")
    #expect(path != nil)
    if let path { #expect(String(cString: path).isEmpty == false) }

    // Wall time is seconds since the Unix epoch (well after 2020-01-01).
    #expect(browser_io_wall_time_seconds() > 1_577_836_800)
    let first = browser_io_monotonic_nanoseconds()
    let second = browser_io_monotonic_nanoseconds()
    #expect(first > 0)
    #expect(second >= first)
  }

  // MARK: - Packet format

  @Test
  func packetWriterAndReaderRoundTripLittleEndianFields() {
    var writer = IOWriter()
    writer.u32(0x0403_0201)
    writer.u64(0x0807_0605_0403_0201)
    writer.f64(-2.5)
    writer.data([9, 8, 7])
    writer.text("héllo")
    #expect(Array(writer.bytes.prefix(4)) == [1, 2, 3, 4])

    var reader = IOReader(bytes: writer.bytes)
    #expect(reader.u32() == 0x0403_0201)
    #expect(reader.u64() == 0x0807_0605_0403_0201)
    #expect(reader.f64() == -2.5)
    #expect(reader.data() == [9, 8, 7])
    #expect(reader.text() == "héllo")
    #expect(reader.finish() == nil)
  }

  @Test
  func packetReaderRejectsTruncatedOversizedAndTrailingResponses() {
    var truncated = IOReader(bytes: [1, 2, 3])
    #expect(truncated.u32() == 0)
    #expect(truncated.error?.code == -8)
    #expect(truncated.error?.message == "Truncated browser host response")
    // Once a read fails, later reads yield empty values and keep the first error.
    #expect(truncated.u64() == 0)
    #expect(truncated.data().isEmpty)
    #expect(truncated.text().isEmpty)
    #expect(truncated.finish()?.message == "Truncated browser host response")

    var oversized = IOReader(bytes: [10, 0, 0, 0, 1, 2])
    #expect(oversized.data().isEmpty)
    #expect(oversized.finish() == BrowserIOError(code: -8, message: "Invalid browser host response length"))

    var trailing = IOReader(bytes: [1, 0, 0, 0, 0xFF])
    #expect(trailing.u32() == 1)
    #expect(trailing.finish() == BrowserIOError(code: -8, message: "Trailing browser host response bytes"))
  }

  // MARK: - Response routing

  @Test
  func responseRouterKeepsStreamingRegistrationsUntilAFinalStatus() {
    let identifier: UInt32 = 0xF0F0_0001
    var received: [(Int32, [UInt8])] = []
    IORuntime.state.withLock { state in
      state.pending[identifier] = { status, bytes in received.append((status, bytes)) }
    }

    // Statuses >= 100 are intermediate (stream chunks, observer events).
    _swiftUIWebReceiveIO(identifier, 100, nil, 0)
    let chunk: [UInt8] = [1, 2, 3]
    chunk.withUnsafeBufferPointer { _swiftUIWebReceiveIO(identifier, 101, $0.baseAddress, 3) }
    #expect(IORuntime.state.withLock { $0.pending[identifier] != nil })

    // A final status removes the registration; later deliveries are dropped.
    _swiftUIWebReceiveIO(identifier, 0, nil, 0)
    _swiftUIWebReceiveIO(identifier, 0, nil, 0)
    #expect(IORuntime.state.withLock { $0.pending[identifier] == nil })
    #expect(received.map { $0.0 } == [100, 101, 0])
    #expect(received.map { $0.1 } == [[], [1, 2, 3], []])

    // Deliveries for identifiers that were never registered are ignored.
    _swiftUIWebReceiveIO(0xF0F0_0002, -6, nil, 0)
  }

  @Test
  func cDeliveryCopiesHostOwnedBytesIntoTheRegisteredCallback() {
    // Any request installs the native response callback in the C adapter.
    BrowserTimer.schedule(after: 0) {}
    let identifier: UInt32 = 0xF0F0_0003
    var received: [(Int32, [UInt8])] = []
    IORuntime.state.withLock { state in
      state.pending[identifier] = { status, bytes in received.append((status, bytes)) }
    }
    let raw = browser_io_alloc(2)!.assumingMemoryBound(to: UInt8.self)
    raw[0] = 0x6F
    raw[1] = 0x6B
    // The adapter takes ownership of host bytes and frees them after delivery.
    browser_io_deliver(identifier, -6, raw, 2)
    #expect(received.count == 1)
    #expect(received.first?.0 == -6)
    #expect(received.first?.1 == Array("ok".utf8))
    #expect(IORuntime.state.withLock { $0.pending[identifier] == nil })
  }

  @Test
  func requestIdentifiersWrapAroundSkippingZeroAndInFlightRequests() {
    let previous = IORuntime.state.withLock { state -> UInt32 in
      let previous = state.nextID
      state.nextID = .max
      state.pending[.max] = { _, _ in }
      return previous
    }
    defer {
      IORuntime.state.withLock { state in
        state.pending.removeValue(forKey: .max)
        state.nextID = previous
      }
    }
    let operation = BrowserTimer.schedule(after: 1) {}
    #expect(operation.identifier != 0)
    #expect(operation.identifier != .max)
    // Identifiers wrapped to the low range. (Not asserted as exactly 1: tests
    // outside this suite may issue timer requests concurrently.)
    #expect(operation.identifier < 1024)
    // A failed request releases its slot immediately.
    #expect(IORuntime.state.withLock { $0.pending[operation.identifier] == nil })
  }

  // MARK: - Cancellation

  @Test
  func operationBoxCancelsAnOperationAssignedAfterCancellation() {
    let box = _BrowserIOOperationBox()
    box.cancel()
    let operation = BrowserTimer.schedule(after: 1) {}
    #expect(!operation.isCancelled)
    box.operation = operation
    #expect(operation.isCancelled)

    let live = _BrowserIOOperationBox()
    let second = BrowserTimer.schedule(after: 1) {}
    live.operation = second
    #expect(!second.isCancelled)
    live.cancel()
    #expect(second.isCancelled)
  }

  @Test
  func alreadyCancelledTasksStillSurfaceTheUnavailableHost() async {
    let request = BrowserHTTPRequest(url: "https://example.test/cancelled")
    let database = BrowserIndexedDB(databaseName: "cancelled")
    let task = Task { @MainActor () -> [Int32] in
      withUnsafeCurrentTask { $0?.cancel() }
      return [
        await browserIOErrorCode { try await BrowserTimer.sleep(for: 1) },
        await browserIOErrorCode { _ = try await BrowserHTTPClient.send(request) },
        await browserIOErrorCode { _ = try await BrowserHTTPClient.stream(request) },
        await browserIOErrorCode { _ = try await database.get("key") },
        await browserIOErrorCode { try await database.put([1], forKey: "key") },
        await browserIOErrorCode { _ = try await database.keys() },
        await browserIOErrorCode { try await database.transaction([.removeAll]) },
      ].map { $0 ?? 0 }
    }
    let codes = await task.value
    #expect(codes == [-7, -7, -7, -7, -7, -7, -7])
  }

  // MARK: - Native failure surface

  @Test
  func timersReportTheMissingHostWithoutFiringTheirCallback() async {
    let operation = BrowserTimer.schedule(after: -5) { Issue.record("timer fired without a host") }
    operation.cancel()
    #expect(operation.isCancelled)
    do {
      try await BrowserTimer.sleep(for: -1)
      Issue.record("expected unavailable BrowserIO host")
    } catch let error as BrowserIOError {
      #expect(error == BrowserIOError(code: -7, message: "Browser host is not installed"))
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }

  @Test
  func httpResponsesDecodeTheirBodyAsUTF8Text() {
    let response = BrowserHTTPResponse(statusCode: 200, url: "https://example.test", headers: [:], body: Array("hé".utf8))
    #expect(response.text == "hé")
    #expect(BrowserHTTPResponse(statusCode: 204, url: "", headers: [:], body: []).text.isEmpty)
  }

  @Test
  func webStorageTransactionsValidateMutationsBeforeReachingTheHost() {
    let storage = BrowserWebStorage(namespace: "contract")
    func code(_ mutations: [BrowserWebStorage.Mutation], expectedRevision: UInt64? = nil) -> Int32? {
      do { try storage.transaction(mutations, expectedRevision: expectedRevision); return nil }
      catch { return error.code }
    }
    let tooMany = [BrowserWebStorage.Mutation](repeating: .remove(key: "k"), count: 100_001)
    #expect(code(tooMany) == -1)
    #expect(code([.set(key: "", value: "v")]) == -1)
    #expect(code([.remove(key: "__revision")]) == -1)
    #expect(code([.set(key: "a", value: "1"), .remove(key: "b")], expectedRevision: 3) == -7)

    do {
      _ = try storage.get("a")
      Issue.record("expected unavailable storage host")
    } catch {
      #expect(error == BrowserIOError(code: -7, message: "Browser storage host is unavailable"))
    }
  }

  @Test
  func windowAndDOMViewRequestsDegradeWithoutAHost() {
    #expect(!BrowserWindow.open("https://example.test/sign-in"))
    let element = BrowserDOMElement(identifier: 7)
    BrowserDOMBridge.domViewMount(component: "stage", state: "{}", on: element)
    BrowserDOMBridge.domViewUpdate(state: "{\"a\":1}", on: element)
    BrowserDOMBridge.domViewUnmount(on: element)
    do {
      _ = try BrowserDOMBridge.mounts()
      Issue.record("expected unavailable DOM host")
    } catch {
      #expect(error.code == -7)
    }
  }

  @Test
  func indexedDBCompletionsReportTheMissingHostSynchronously() async {
    let database = BrowserIndexedDB(databaseName: "contract", version: 3)
    #expect(database.databaseName == "contract")
    #expect(database.version == 3)
    var codes: [Int32] = []
    func record<T>(_ result: Result<T, BrowserIOError>) {
      switch result {
      case .success: codes.append(0)
      case .failure(let error): codes.append(error.code)
      }
    }
    database.get("key") { record($0) }
    database.put([1, 2], forKey: "key") { record($0) }
    database.remove("key") { record($0) }
    database.removeAll { record($0) }
    database.keys { record($0) }
    #expect(codes == [-7, -7, -7, -7, -7])

    let removed = await browserIOErrorCode { try await database.remove("key") }
    let cleared = await browserIOErrorCode { try await database.removeAll() }
    let listed = await browserIOErrorCode { _ = try await database.keys() }
    let committed = await browserIOErrorCode {
      try await database.transaction([.put(key: "a", value: [1]), .remove(key: "b"), .removeAll])
    }
    #expect([removed, cleared, listed, committed] == [-7, -7, -7, -7])
    let tooMany = [BrowserIndexedDB.Mutation](repeating: .removeAll, count: 100_001)
    let rejected = await browserIOErrorCode { try await database.transaction(tooMany) }
    #expect(rejected == -1)
  }

  @Test
  func secureStoreReportsUnavailableWithoutWebCrypto() async {
    let store = BrowserSecureStore(name: "contract")
    #expect(store.name == "contract")
    let loaded = await browserIOErrorCode { _ = try await store.loadAll() }
    let saved = await browserIOErrorCode { try await store.save([1, 2, 3], id: "item") }
    let removed = await browserIOErrorCode { try await store.remove(id: "item") }
    let cleared = await browserIOErrorCode { try await store.removeAll() }
    #expect([loaded, saved, removed, cleared] == [-7, -7, -7, -7])
  }
}
