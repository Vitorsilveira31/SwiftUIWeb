import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Browser) import SwiftUIWebTransferable
import SwiftUIWebPhotosUI

@Suite(.processGlobalState)
@MainActor
final class TransferableTests {
  private struct Card: Codable, Transferable, Equatable {
    let title: String
    let count: Int

    static var transferRepresentation: some TransferRepresentation {
      CodableRepresentation(for: Card.self, contentType: .json)
    }
  }

  private struct TextFile: Transferable, Equatable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
      FileRepresentation<TextFile>(contentType: .plainText, exporting: { value in
        SentTransferredFile(SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(
          data: Data(value.value.utf8),
          contentType: .plainText,
          suggestedFileName: "value.txt"
        )))
      }, importing: { file in
        let loaded = try await SwiftUIWebFileRuntime.load(file.file)
        return TextFile(value: String(decoding: loaded?.data ?? Data(), as: UTF8.self))
      })
    }
  }

  private struct MultiFormat: Transferable, Equatable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
      DataRepresentation<MultiFormat>(contentType: .json, exporting: { value in
        Data(value.value.utf8)
      }, importing: { data in
        MultiFormat(value: String(decoding: data, as: UTF8.self))
      })
      DataRepresentation<MultiFormat>(contentType: .plainText, exporting: { value in
        Data(value.value.utf8)
      }, importing: { data in
        MultiFormat(value: String(decoding: data, as: UTF8.self))
      })
    }
  }

  @Test
  func testCodableTransferableRoundTripsThroughAllChannels() async throws {
    let card = Card(title: "Inbox", count: 3)
    _expectEqual(Card.exportedContentTypes(), [.json])
    _expectEqual(Card.exportedContentTypes(visibility: .all), [.json])
    let encoded = try await card.exported(as: nil)
    let decoded = try await Card.importing(data: encoded)
    _expectEqual(decoded, card)
    let channels: [SwiftUIWebTransferChannel] = [.clipboard, .dragAndDrop, .fileImporter, .fileExporter, .photos, .webShare, .generic]

    for channel in channels {
      let item = try await SwiftUIWebTransferRuntime.export(card, channel: channel)
      _expectEqual(item.channel, channel)
      _expectEqual(item.metadata.contentTypes, [.json])
      let decoded = try await SwiftUIWebTransferRuntime.load(item, as: Card.self)
      _expectEqual(decoded, card)
      SwiftUIWebTransferRuntime.remove(item)
      _expectNil(SwiftUIWebTransferRuntime.metadata(for: item.identifier))
    }
  }

  @Test
  func testPreferredContentTypeSelectsOneSharedRepresentation() async throws {
    let value = MultiFormat(value: "hello")
    let payloads = try await SwiftUIWebTransferRuntime.exportPayloads(value)
    _expectEqual(payloads.map(\.contentType), [.json, .plainText])
    let item = try await SwiftUIWebTransferRuntime.export(value, for: .clipboard, preferredContentType: .plainText)
    _expectEqual(item.metadata.contentTypes, [.plainText])
    let loaded = try await SwiftUIWebTransferRuntime.load(item, as: MultiFormat.self)
    _expectEqual(loaded, value)
    SwiftUIWebTransferRuntime.remove(item)
  }

  @Test
  func testFileRepresentationUsesTheSameRuntimePath() async throws {
    let original = TextFile(value: "hello")
    let item = try await SwiftUIWebTransferRuntime.export(original, channel: .fileExporter)
    _expectEqual(item.metadata.suggestedFileName, "value.txt")
    let loaded = try await SwiftUIWebTransferRuntime.load(item, as: TextFile.self)
    _expectEqual(loaded, original)
    SwiftUIWebTransferRuntime.remove(item)
  }

  @Test
  func testPhotosPickerUsesTheSameCodableTransferable() async throws {
    let card = Card(title: "Photo", count: 1)
    let exported = try await SwiftUIWebTransferRuntime.export(card, for: .photos)
    let pickerItem = PhotosPickerItem(itemIdentifier: exported.identifier, supportedContentTypes: [.json])
    let loaded = try await pickerItem.loadTransferable(type: Card.self)
    _expectEqual(loaded, card)
    SwiftUIWebTransferRuntime.remove(exported)
  }

  @Test
  func testTransferItemLeasesReleaseTemporaryPayloads() async throws {
    let item = try await SwiftUIWebTransferRuntime.export("leased", for: .clipboard)
    var first: SwiftUIWebTransferLease? = item.lease()
    var second: SwiftUIWebTransferLease? = item.lease()
    _expectNotNil(SwiftUIWebTransferRuntime.metadata(for: item.identifier))
    _ = (first, second)
    first = nil
    _expectNotNil(SwiftUIWebTransferRuntime.metadata(for: item.identifier))
    second = nil
    _expectNil(SwiftUIWebTransferRuntime.metadata(for: item.identifier))
  }

  @Test
  func testAsyncLoaderAndCleanupRunOnRelease() async throws {
    let identifier = "transfer-test-cleanup"
    let cleaned = LockedFlag()
    let started = LockedFlag()
    // The loader sleeps far longer than the test can take, so only the release can end it: a short sleep let a
    // busy main actor see the load finish before it released the transfer.
    SwiftUIWebTransferRuntime.register(
      identifier: identifier,
      metadata: SwiftUIWebTransferMetadata(contentTypes: [.plainText], size: 5),
      loader: { _ in
        started.set()
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return SwiftUIWebTransferPayload(data: Data("hello".utf8), contentType: .plainText)
      },
      cleanup: { cleaned.set() }
    )

    let loading = Task { try await SwiftUIWebTransferRuntime.load(identifier: identifier) }
    // Release only once the load is really in flight: with every suite on the main
    // actor, a fixed short sleep can end before the load task has started.
    while !started.value { await Task.yield() }
    SwiftUIWebTransferRuntime.release(identifier: identifier)
    do {
      _ = try await loading.value
      _fail("a released transfer should cancel its in-flight load")
    } catch is CancellationError {
      // Expected: release cancels the browser file/blob read.
    }
    _expectTrue(cleaned.value)
    _expectNil(SwiftUIWebTransferRuntime.metadata(for: identifier))
  }

  @Test
  func exportOnlyAndImportOnlyRepresentationsAdvertiseOneDirection() async throws {
    _expectEqual(Labelled.exportedContentTypes(), [.json])
    _expectEqual(Labelled.importedContentTypes(), [.plainText])
    let value = Labelled(value: "one-way")
    _expectEqual(value.exportedContentTypes(), [.json])
    _expectEqual(value.importedContentTypes(), [.plainText])
    let exported = try await value.exported(as: nil)
    _expectEqual(exported, Data("one-way".utf8))
    let imported = try await Labelled.importing(data: Data("back".utf8), contentType: .plainText)
    _expectEqual(imported, Labelled(value: "back"))
  }

  @Test
  func proxyRepresentationsCoverEverySyncAndAsyncPairing() async throws {
    let exported = try await AsyncExportProxy(value: "a").exported(as: nil)
    _expectEqual(exported, Data("a".utf8))
    let syncImported = try await SyncImportProxy.importing(data: Data("b".utf8), contentType: nil)
    _expectEqual(syncImported.value, "b")
    let asyncImported = try await AsyncImportProxy.importing(data: Data("c".utf8), contentType: nil)
    _expectEqual(asyncImported.value, "c")
    let asyncData = try await AsyncRoundTripProxy(value: "d").exported(as: nil)
    let asyncRoundTrip = try await AsyncRoundTripProxy.importing(data: asyncData, contentType: nil)
    _expectEqual(asyncRoundTrip.value, "d")
    let mixedData = try await MixedRoundTripProxy(value: "e").exported(as: nil)
    let mixedRoundTrip = try await MixedRoundTripProxy.importing(data: mixedData, contentType: nil)
    _expectEqual(mixedRoundTrip.value, "e")
  }

  @Test
  func builderBlocksAcceptEveryArityFromThreeToTen() {
    let types: [UTType] = [.json, .plainText, .utf8PlainText, .html, .xml, .png, .jpeg, .pdf, .rtf, .commaSeparatedText]
    let parts = types.map { type in
      DataRepresentation<Labelled>(exportedContentType: type, exporting: { Data($0.value.utf8) })
    }
    func exported<R: TransferRepresentation>(_ representation: R) -> [UTType] where R.Item == Labelled {
      representation._swiftUIWebErased().exportedContentTypes
    }
    typealias Builder = TransferRepresentationBuilder<Labelled>
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2])), Array(types[0..<3]))
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3])), Array(types[0..<4]))
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3], parts[4])), Array(types[0..<5]))
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])), Array(types[0..<6]))
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6])), Array(types[0..<7]))
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7])), Array(types[0..<8]))
    _expectEqual(
      exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8])),
      Array(types[0..<9])
    )
    _expectEqual(
      exported(Builder.buildBlock(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8], parts[9])),
      types
    )
    // A block presents the same representations through its body.
    _expectEqual(exported(Builder.buildBlock(parts[0], parts[1], parts[2]).body), Array(types[0..<3]))
  }

  @Test
  func suggestedFileNamesTravelWithTheExportedPayload() async throws {
    let payload = try await FixedName(value: "x")._swiftUIWebExport()
    _expectEqual(payload.suggestedFileName, "fixed.json")
    _expectEqual(payload.data, Data("x".utf8))
  }

  @Test
  func erasedRepresentationsExportEveryAdvertisedFormatOnce() async throws {
    let erased = SwiftUIWebAnyTransferRepresentation(MultiFormat.transferRepresentation)
    let value = MultiFormat(value: "hi")
    let all = try await erased.exportAll(value)
    _expectEqual(all.map(\.contentType), [.json, .plainText])
    let plain = try await erased.exportAll(value, preferredContentTypes: [.plainText])
    _expectEqual(plain.map(\.contentType), [.plainText])
    let fallback = try await erased.exportAll(value, preferredContentTypes: [])
    _expectEqual(fallback.map(\.contentType), [.json])
  }

  @Test
  func exportAllRethrowsWhenEveryFormatRefuses() async {
    let erased = SwiftUIWebAnyTransferRepresentation(RefusingExport.transferRepresentation)
    do {
      _ = try await erased.exportAll(RefusingExport())
      _fail("a refused export must not produce payloads")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.message, "exporter refused")
    } catch {
      _fail("unexpected error \(error)")
    }
  }

  @Test
  func fileRepresentationReportsAnExportedFileThatIsGone() async {
    do {
      _ = try await VanishingFile()._swiftUIWebExport()
      _fail("an export whose file vanished must fail")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    } catch {
      _fail("unexpected error \(error)")
    }
  }

  @Test
  func exportedFileNamesStayAsASingleLeafInsideTheDestinationDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("transferable-confinement-\(UUID().uuidString)", isDirectory: true)
    let directory = root.appendingPathComponent("export", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data("payload".utf8)

    func write(_ name: String?) throws -> URL {
      try SwiftUIWebFileRuntime.write(
        SwiftUIWebTransferPayload(data: bytes, contentType: .plainText, suggestedFileName: name),
        into: directory
      )
    }
    func expectWritten(_ name: String?, to leaf: String) throws {
      let written = try write(name)
      _expectEqual(written.standardizedFileURL.path, directory.appendingPathComponent(leaf).standardizedFileURL.path)
    }

    // Directory components are dropped: a traversal name is written as its leaf, inside the directory.
    try expectWritten("../escape.txt", to: "escape.txt")
    try expectWritten("nested/dir/deep.txt", to: "deep.txt")
    _expectEqual(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path), false)

    // Names with no usable leaf fall back to the default name.
    try expectWritten(nil, to: "item")
    try expectWritten("", to: "item")
    try expectWritten(".", to: "item")
    try expectWritten("..", to: "item")
    try expectWritten("sub/..", to: "item")
    try expectWritten("bad\u{0}name.txt", to: "item")

    // Ordinary names are written exactly where they always were, overwriting an existing file.
    try expectWritten("report.txt", to: "report.txt")
    _expectEqual(try Data(contentsOf: directory.appendingPathComponent("report.txt")), bytes)
    _ = try SwiftUIWebFileRuntime.write(
      SwiftUIWebTransferPayload(data: Data("second".utf8), contentType: .plainText, suggestedFileName: "report.txt"),
      into: directory
    )
    _expectEqual(try Data(contentsOf: directory.appendingPathComponent("report.txt")), Data("second".utf8))

    // A literal percent in the name stays literal: the returned URL names the file that was written.
    let escaped = try write("report%2026.txt")
    _expectEqual(try Data(contentsOf: escaped), bytes)
    _expectEqual(escaped.lastPathComponent, "report%2026.txt")
  }

  @Test
  func fileTransfersWriteReadAndImportThroughTheRuntimeAndTheFileSystem() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("transferable-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    // Without a suggested name the written file is called "item".
    let written = try await "hello".export(to: directory, contentType: .plainText)
    _expectEqual(written.lastPathComponent, "item")
    let contents = try Data(contentsOf: written)
    _expectEqual(contents, Data("hello".utf8))

    // The scoped form hands the handler a runtime file URL that loads the same bytes.
    let scoped = try await loadThroughScopedExport("scoped")
    _expectEqual(scoped?.data, Data("scoped".utf8))

    // Importing a file reads it from disk and imports its bytes.
    let source = directory.appendingPathComponent("import.txt")
    try Data("from disk".utf8).write(to: source)
    let imported = try await String(importing: source, contentType: nil)
    _expectEqual(imported, "from disk")

    // A runtime file URL whose payload was released has nothing to import.
    do {
      _ = try await String(importing: SwiftUIWebFileRuntime.url(identifier: "never-registered"), contentType: nil)
      _fail("a released runtime file must not import")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    }
  }

  @Test
  func typeHelpersNameMimeTypesAndFilenameExtensions() {
    _expectEqual(UTType.png.mimeType, "image/png")
    _expectEqual(UTType.from(filenameExtension: "png"), .png)
    _expectEqual(UTType.from(mimeType: "application/json; charset=utf-8"), .json)
    _expectEqual(UTType.from(mimeType: "image/png"), .png)
    _expectTrue(UTType.png.isImage)
    _expectTrue(UTType.from(mimeType: "video/mp4").isVideo)
  }

  @Test
  func transferErrorsDescribeThemselvesAndPayloadsExposeTheirBytes() {
    _expectEqual(SwiftUIWebTransferError(.invalidData).description, "invalidData")
    _expectEqual(SwiftUIWebTransferError(.cancelled, message: "stopped").description, "stopped")
    let payload = SwiftUIWebTransferPayload(data: Data([1, 2]), contentType: .data)
    _expectEqual(payload.bytes, Data([1, 2]))
    _expectEqual(SwiftUIWebTransferMetadata(contentTypes: [.png, .jpeg]).contentType, .png)
    _expectNil(SwiftUIWebTransferMetadata(contentTypes: []).contentType)
  }

  @Test
  func transferLeasesCompareByIdentityNotByIdentifier() async throws {
    SwiftUIWebTransferRuntime.register(
      identifier: "lease-identity",
      payload: SwiftUIWebTransferPayload(data: Data([1]), contentType: .data)
    )
    let first = SwiftUIWebTransferLease(identifier: "lease-identity")
    let second = SwiftUIWebTransferLease(identifier: "lease-identity")
    _expectEqual(first, first)
    _expectNotEqual(first, second)
    _expectEqual(Set([first, first, second]).count, 2)
    SwiftUIWebTransferRuntime.remove(identifier: "lease-identity")
  }

  @Test
  func registeredLoadersServeTypedValuesAndReleaseTheirCleanup() async throws {
    let cleaned = LockedFlag()
    SwiftUIWebTransferRuntime._register(
      identifier: "registered-loader",
      metadata: SwiftUIWebTransferMetadata(contentTypes: [.plainText], size: 4),
      loader: { _ in SwiftUIWebTransferPayload(data: Data("lazy".utf8), contentType: .plainText) },
      cleanup: { cleaned.set() }
    )
    _expectEqual(SwiftUIWebTransferRuntime.metadata(for: "registered-loader")?.size, 4)
    let text = try await SwiftUIWebTransferRuntime.load(identifier: "registered-loader", as: String.self)
    _expectEqual(text, "lazy")
    SwiftUIWebTransferRuntime.remove(identifier: "registered-loader")
    _expectTrue(cleaned.value)

    // A loader that yields nothing reports no value and keeps the record's metadata.
    SwiftUIWebTransferRuntime._register(
      identifier: "empty-loader",
      metadata: SwiftUIWebTransferMetadata(contentTypes: [.plainText]),
      loader: { _ in nil }
    )
    let empty = try await SwiftUIWebTransferRuntime.load(identifier: "empty-loader", as: String.self)
    _expectNil(empty)
    _expectNotNil(SwiftUIWebTransferRuntime.metadata(for: "empty-loader"))
    SwiftUIWebTransferRuntime.remove(identifier: "empty-loader")
  }
}

/// Reads the runtime file that `withExportedFile` hands its handler. Kept outside the main-actor test so the handler
/// closure is not sent across an isolation boundary.
private func loadThroughScopedExport(_ text: String) async throws -> SwiftUIWebTransferFile? {
  try await text.withExportedFile(contentType: .plainText) { url in
    try await SwiftUIWebFileRuntime.load(url)
  }
}

/// Exports and imports a text value as JSON or plain text, to exercise multi-format builders.
private struct Labelled: Transferable, Equatable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<Labelled>(exportedContentType: .json, exporting: { Data($0.value.utf8) })
    DataRepresentation<Labelled>(importedContentType: .plainText, importing: { Labelled(value: String(decoding: $0, as: UTF8.self)) })
  }
}

private struct AsyncExportProxy: Transferable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation<AsyncExportProxy, String>(exporting: { (item: AsyncExportProxy) async throws -> String in item.value })
  }
}

private struct SyncImportProxy: Transferable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation<SyncImportProxy, String>(importing: { (text: String) throws -> SyncImportProxy in SyncImportProxy(value: text) })
  }
}

private struct AsyncImportProxy: Transferable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation<AsyncImportProxy, String>(importing: { (text: String) async throws -> AsyncImportProxy in AsyncImportProxy(value: text) })
  }
}

private struct AsyncRoundTripProxy: Transferable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation<AsyncRoundTripProxy, String>(
      exporting: { (item: AsyncRoundTripProxy) async throws -> String in item.value },
      importing: { (text: String) async throws -> AsyncRoundTripProxy in AsyncRoundTripProxy(value: text) }
    )
  }
}

private struct MixedRoundTripProxy: Transferable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation<MixedRoundTripProxy, String>(
      exporting: { (item: MixedRoundTripProxy) throws -> String in item.value },
      importing: { (text: String) async throws -> MixedRoundTripProxy in MixedRoundTripProxy(value: text) }
    )
  }
}

private struct FixedName: Transferable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<FixedName>(exportedContentType: .json, exporting: { Data($0.value.utf8) })
      .suggestedFileName("fixed.json")
  }
}

private struct RefusingExport: Transferable {
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<RefusingExport>(exportedContentType: .json, exporting: { _ in
      throw SwiftUIWebTransferError(.invalidData, message: "exporter refused")
    })
  }
}

private struct VanishingFile: Transferable {
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation<VanishingFile>(exportedContentType: .plainText, exporting: { _ in
      SentTransferredFile(SwiftUIWebFileRuntime.url(identifier: "vanished-file"))
    })
  }
}

private final class LockedFlag: @unchecked Sendable {
  private var storage = false
  private let lock = NSLock()
  var value: Bool { lock.lock(); defer { lock.unlock() }; return storage }
  func set() { lock.lock(); storage = true; lock.unlock() }
}
