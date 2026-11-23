/// A headless JavaScript service of the page: an SDK without a view of its own, such as analytics, error monitoring,
/// purchases or messaging. A page script registers it with `SwiftUIWebServices.define(name, factory)` ("Page services" in
/// Documentation/BROWSER_APP_SHELL.md); its factory runs on the first call or observation, so the SDK is fetched only
/// once the app uses it. Payloads and results are text, JSON by convention. The service always runs on the page's main
/// thread, next to the document its SDK needs, also when the app itself runs in a worker.
public struct BrowserService: Sendable {
  public let name: String

  public init(_ name: String) { self.name = name }

  /// Calls `method` with `payload` and delivers the text it returns (empty for none). A service that is not defined
  /// within a few seconds, a missing method and a method that throws all fail with a `BrowserIOError`.
  @discardableResult
  public func call(_ method: String, _ payload: String = "",
                   completion: @escaping @Sendable (Result<String, BrowserIOError>) -> Void) -> BrowserIOOperation {
    var writer = IOWriter()
    writer.text(name)
    writer.text(method)
    writer.text(payload)
    return IORuntime.send(_BrowserIOProtocol.service, writer) { status, bytes in
      if status < 0 { completion(.failure(IORuntime.error(status, bytes))); return }
      var input = IOReader(bytes: bytes)
      let text = input.text()
      if let error = input.finish() { completion(.failure(error)); return }
      completion(.success(text))
    }
  }

  /// Async/await form of `call(_:_:completion:)`. Cancelling the task stops waiting for the result; the page may still
  /// finish the call.
  public func call(_ method: String, _ payload: String = "") async throws -> String {
    let box = _BrowserIOOperationBox()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
        box.operation = call(method, payload) { result in
          switch result {
          case .success(let text): continuation.resume(returning: text)
          case .failure(let error): continuation.resume(throwing: error)
          }
        }
      }
    }, onCancel: {
      box.cancel()
    })
  }

  /// Calls `method` without waiting for its result, for calls whose outcome the app does not act on (recording an
  /// analytics event, adding a breadcrumb).
  public func send(_ method: String, _ payload: String = "") {
    call(method, payload) { _ in }
  }

  /// Delivers each payload the service emits as `event` (`emit(event, payload)` in its factory's context) until the
  /// returned operation is cancelled. Observing also starts the service, so an SDK that only produces events begins
  /// listening.
  @discardableResult
  public func observe(_ event: String, _ receive: @escaping (String) -> Void) -> BrowserIOOperation {
    var writer = IOWriter()
    writer.text(name)
    writer.text(event)
    return IORuntime.send(_BrowserIOProtocol.serviceEvents, writer) { status, bytes in
      guard status == _BrowserIOEvent.serviceEvent else { return }
      var input = IOReader(bytes: bytes)
      let text = input.text()
      guard input.finish() == nil else { return }
      receive(text)
    }
  }
}
