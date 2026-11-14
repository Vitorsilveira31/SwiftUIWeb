/// Encrypted item records for `WebSecurity`. The browser host encrypts each value with AES-GCM under
/// a non-extractable Web Crypto key kept in IndexedDB, and binds it to its item id; Swift exchanges
/// only item ids and plaintext bytes, never key material. Web Crypto needs a secure context: over
/// plain HTTP every call fails with code -7.
public struct BrowserSecureStore: Sendable {
  public let name: String

  public init(name: String = "keychain") {
    precondition(!name.isEmpty && name.utf8.count <= 256)
    self.name = name
  }

  /// Every item that still decrypts, keyed by id. A record that no longer decrypts under the
  /// store's key is left out rather than returned as garbage.
  public func loadAll() async throws(BrowserIOError) -> [(id: String, value: [UInt8])] {
    let bytes = try await perform(0)
    var input = IOReader(bytes: bytes)
    let count = Int(input.u32())
    guard input.error == nil, count <= 100_000 else {
      throw input.error ?? BrowserIOError(code: -8, message: "Invalid secure store item count")
    }
    var items: [(id: String, value: [UInt8])] = []
    items.reserveCapacity(count)
    for _ in 0..<count { items.append((id: input.text(), value: input.data())) }
    if let error = input.finish() { throw error }
    return items
  }

  public func save(_ value: [UInt8], id: String) async throws(BrowserIOError) { try await mutate(1, id: id, value: value) }
  public func remove(id: String) async throws(BrowserIOError) { try await mutate(2, id: id) }
  public func removeAll() async throws(BrowserIOError) { try await mutate(3) }

  private func mutate(_ action: UInt32, id: String = "", value: [UInt8] = []) async throws(BrowserIOError) {
    let bytes = try await perform(action, id: id, value: value)
    guard bytes.isEmpty else { throw BrowserIOError(code: -8, message: "Unexpected secure store write result") }
  }

  /// Typed errors, so callers can tell "unavailable" (-7) from other failures without a dynamic
  /// cast, which Embedded Swift does not have.
  private func perform(_ action: UInt32, id: String = "", value: [UInt8] = []) async throws(BrowserIOError) -> [UInt8] {
    var command = IOWriter()
    command.text(name); command.u32(action); command.text(id); command.data(value)
    let box = _BrowserIOOperationBox()
    let result = await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { (continuation: CheckedContinuation<Result<[UInt8], BrowserIOError>, Never>) in
        box.operation = IORuntime.send(_BrowserIOProtocol.secureStore, command) { status, bytes in
          continuation.resume(returning: status < 0 ? .failure(IORuntime.error(status, bytes)) : .success(bytes))
        }
      }
    }, onCancel: { box.cancel() })
    return try result.get()
  }
}
