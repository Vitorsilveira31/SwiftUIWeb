import Testing
@_spi(Browser) @testable import SwiftUIWebBrowser
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) @testable import SwiftUIWebTransferable
@testable import SwiftUIWebWeb

/// Values that come from storage, the URL, the file system and the page must not trap, alias another value, or grow
/// without bound. The private encoders (`<base>` placement, the history quote, the navigation href) are checked by the
/// browser suites.
@Suite(.serialized, .processGlobalState)
@MainActor
struct StateFileHardeningTests {
  /// An in-memory app scope for the defaults tests; removed when the test ends.
  private final class MemoryStore: @unchecked Sendable {
    var values: [String: String] = [:]
    func install() {
      StorageRuntime.install(StorageAdapter(read: { self.values[$0] }, write: { self.values[$0] = $1 }, remove: { self.values[$0] = nil }))
    }
  }

  @Test func storedStringArrayKeepsElementsThatContainTheSeparator() {
    let store = MemoryStore()
    store.install()
    defer { StorageRuntime.install(nil) }
    let suite = _WebUserDefaults(suiteName: "state-hardening-array")!
    let value = ["a\u{1F}b", "", "c"]
    suite.set(value, forKey: "list")
    #expect(suite._object(forKey: "list", as: [String].self) == value)
  }

  @Test func framedStringArrayWithAnImpossibleLengthReadsAsNothing() {
    let store = MemoryStore()
    store.install()
    defer { StorageRuntime.install(nil) }
    let suite = _WebUserDefaults(suiteName: "state-hardening-length")!
    // Past the bytes there are, and past Int: refused before the length could overflow (32 bits in the browser build).
    suite.set("\u{1E}2147483648\u{1E}", forKey: "long")
    suite.set("\u{1E}99999999999999999999999\u{1E}x", forKey: "huge")
    #expect(suite._object(forKey: "long", as: [String].self) == nil)
    #expect(suite._object(forKey: "huge", as: [String].self) == nil)
  }

  @Test func indexedDBNamesWithoutADotKeepTheirDatabase() {
    #expect(_webIndexedDBPhysicalName("drafts", "records") == "drafts.records")
    #expect(_webIndexedDBPhysicalName("a.b", "c") != _webIndexedDBPhysicalName("a", "b.c"))
    // A framed name has no "." at all, so it is never the legacy name ("db.store") of another pair.
    #expect(!_webIndexedDBPhysicalName("a.b", "c").contains("."))
    #expect(_webIndexedDBLegacyName(".1:a3:b", "c") != _webIndexedDBPhysicalName("a", "b.c"))
    for (database, store) in [("a", "b.c"), ("a.b", "c"), (".x", "y"), ("%2E", "."), ("a.", ".b")] {
      #expect(!_webIndexedDBPhysicalName(database, store).contains("."))
    }
    #expect(_webIndexedDBPhysicalName("a%2Eb", "c") != _webIndexedDBPhysicalName("a.b", "c"))
  }

  @Test func baseGoesAfterTheDoctypeAndNeverIntoAComment() {
    let base = URL(string: "https://app.example.test/")!
    let html = "<!-- <head> --><!DOCTYPE html><html><head><title>x</title></head></html>"
    #expect(_webHTMLWithBaseURL(html, baseURL: base) == "<!-- <head> --><!DOCTYPE html><base href=\"https://app.example.test/\"><html><head><title>x</title></head></html>")
    #expect(_webHTMLWithBaseURL("<p>hi</p>", baseURL: base) == "<base href=\"https://app.example.test/\"><p>hi</p>")
  }

  @Test func legacyJoinedStringArrayStillReads() {
    let store = MemoryStore()
    store.install()
    defer { StorageRuntime.install(nil) }
    let suite = _WebUserDefaults(suiteName: "state-hardening-legacy")!
    suite.set("a\u{1F}b", forKey: "legacy")
    #expect(suite._object(forKey: "legacy", as: [String].self) == ["a", "b"])
  }

  @Test func documentPathEscapesDotSegments() {
    #expect(_documentPath(["..", ".", "a"]) == "a")
  }

  @Test func virtualFileSystemRefusesRemovingTheRoot() {
    let fs = _VirtualFileSystem.shared
    #expect(throws: FileSystemError.self) { try fs.remove("/") }
    #expect(fs.isDirectory("/"))
  }

  @Test func appendingToADirectoryThrowsAndLeavesTheTree() throws {
    let fs = _VirtualFileSystem.shared
    try fs.makeDirectory("/tmp/state-hardening-dir", intermediate: false)
    #expect(throws: FileSystemError.self) { try fs.appendToFile(Array("x".utf8), at: "/tmp/state-hardening-dir") }
    #expect(fs.isDirectory("/tmp/state-hardening-dir"))
    #expect(fs.file(at: "/tmp/state-hardening-dir") == nil)
  }

  @Test func makeDirectoryCreatesMissingAncestorsWithoutRecursion() throws {
    let fs = _VirtualFileSystem.shared
    try fs.makeDirectory("/tmp/state-hardening/a/b/c", intermediate: true)
    #expect(fs.isDirectory("/tmp/state-hardening/a"))
    #expect(fs.isDirectory("/tmp/state-hardening/a/b/c"))
    #expect(throws: FileSystemError.self) { try fs.makeDirectory("/tmp/state-hardening-missing/x/y", intermediate: false) }
  }

  @Test func emptyIndexedDBNameIsRefusedWithoutTrapping() async {
    let store = WebIndexedDBStore<String>(databaseName: "", objectStoreName: "records")
    await #expect(throws: WebIndexedDBError.self) { try await store.save("value", key: "key") }
  }

  @Test func indexedDBNamesWithDotsDoNotAlias() async throws {
    let first = WebIndexedDBStore<String>(databaseName: "state-hardening.a.b", objectStoreName: "c")
    let second = WebIndexedDBStore<String>(databaseName: "state-hardening.a", objectStoreName: "b.c")
    try await first.save("one", key: "key")
    #expect(try await second.load(key: "key") == nil)
    #expect(try await first.load(key: "key") == "one")
  }

  @Test func byteBufferRefusesAboveItsLimit() {
    var buffer = _EmbeddedByteBuffer()
    #expect(buffer.reserve(_EmbeddedByteBuffer.limit + 1) == nil)
  }

  @Test func inlineTransferIdentifiersAreNotSequential() {
    let first = _EmbeddedTransferIDs.shared.next("embedded-import-")
    let second = _EmbeddedTransferIDs.shared.next("embedded-import-")
    // A random part between the prefix and the counter: "embedded-import-1" names nothing.
    #expect(first != second)
    #expect(first.dropFirst("embedded-import-".count).contains("-"))
    #expect(first.utf8.count > "embedded-import-".utf8.count + 8)
  }

  @Test func urlPayloadIdentifiersAreNotSequential() async throws {
    let first = SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(data: Data([1]), contentType: .data))
    let second = SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(data: Data([2]), contentType: .data))
    #expect(first.absoluteString != second.absoluteString)
    #expect(try await SwiftUIWebFileRuntime.load(first)?.data == Data([1]))
    #expect(try await SwiftUIWebFileRuntime.load(second)?.data == Data([2]))
  }

  @Test func prefetchManifestIsBounded() {
    var registrations: [_WebPrefetchRegistration] = []
    for index in 0..<600 {
      registrations.append(WebPrefetchRuntime.register(_WebPrefetchResource(url: "/state-hardening/\(index)", kind: .data, trigger: .route("state-hardening"))))
    }
    #expect(WebPrefetchRuntime._registeredResources().count <= 512)
    registrations.forEach { $0.cancel() }
  }
}
