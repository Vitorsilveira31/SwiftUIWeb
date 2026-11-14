import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebTransferable

private enum TransferContractFailure: Error, Equatable {
  case export
  case importValue
}

private struct LegacyTransferValue: Transferable, Equatable {
  let value: String

  init(value: String) { self.value = value }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<LegacyTransferValue>(importedContentType: .plainText) { data in
      LegacyTransferValue(value: String(decoding: data, as: UTF8.self))
    }
  }
}

private struct TransferProxy: Transferable, Equatable {
  let text: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<TransferProxy>(
      contentType: .plainText,
      exporting: { Data($0.text.utf8) },
      importing: { TransferProxy(text: String(decoding: $0, as: UTF8.self)) }
    )
  }
}

private struct WrappedTransferValue: Transferable, Equatable {
  let text: String

  static var transferRepresentation: some TransferRepresentation {
    ProxyRepresentation<WrappedTransferValue, TransferProxy>(
      exporting: { TransferProxy(text: $0.text) },
      importing: { WrappedTransferValue(text: $0.text) }
    )
  }
}

private struct CodableTransferValue: Codable, Transferable, Equatable {
  let displayName: String

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(for: CodableTransferValue.self, contentType: .json)
  }
}

private struct MultiFormatTransferValue: Transferable, Equatable {
  let value: String

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation<MultiFormatTransferValue>(
      contentType: .plainText,
      exporting: { Data($0.value.utf8) },
      importing: { MultiFormatTransferValue(value: String(decoding: $0, as: UTF8.self)) }
    )
    DataRepresentation<MultiFormatTransferValue>(
      contentType: .json,
      exporting: { Data($0.value.utf8) },
      importing: { MultiFormatTransferValue(value: String(decoding: $0, as: UTF8.self)) }
    )
  }
}

@Suite(.processGlobalState)
@MainActor
struct TransferableContractsTests {
  @Test
  func contentTypeHelpersNormalizeMimeAndExposeTransferMetadata() {
    let plainText = UTType.from(mimeType: "Text/Plain; charset=utf-8")
    _expectEqual(plainText, .plainText)
    _expectEqual(plainText.mimeType, "text/plain")
    _expectFalse(plainText.isImage)
    _expectFalse(plainText.isVideo)

    let customImage = UTType.from(mimeType: "image/x-custom")
    _expectEqual(customImage.identifier, "image/x-custom")
    _expectTrue(customImage.isImage)
    _expectTrue(customImage.conforms(to: .image))
    _expectEqual(UTType.from(filenameExtension: "notes.txt"), .plainText)
    _expectEqual(UTType.from(filenameExtension: "unknown-extension"), .data)

    let bytes = Data([UInt8(65), 66, 67])
    let payload = SwiftUIWebTransferPayload(
      data: bytes,
      contentType: .plainText,
      suggestedFileName: "notes.txt"
    )
    _expectEqual(payload.bytes, bytes)
    _expectEqual(payload.suggestedFileName, "notes.txt")
    _expectEqual(SwiftUIWebTransferMetadata(contentTypes: []).contentType, nil)
    _expectEqual(SwiftUIWebTransferMetadata(contentType: .plainText).contentType, .plainText)
    _expectEqual(SwiftUIWebTransferError(.cancelled).description, "cancelled")
  }

  @Test
  func transferableBuilderAdvertisesAndRoundTripsMultipleFormats() async throws {
    let value = MultiFormatTransferValue(value: "two formats")
    _expectEqual(MultiFormatTransferValue.exportedContentTypes(), [.plainText, .json])
    _expectEqual(
      MultiFormatTransferValue.exportedContentTypes(visibility: .all),
      [.plainText, .json]
    )
    _expectEqual(MultiFormatTransferValue.importedContentTypes(), [.plainText, .json])

    let payloads = try await value._swiftUIWebExportAll()
    _expectEqual(payloads.map(\.contentType), [.plainText, .json])
    let imported = try await MultiFormatTransferValue.importing(
      data: payloads[1].data,
      contentType: payloads[1].contentType
    )
    _expectEqual(imported, value)
  }

  @Test
  func representationModifiersPreserveExistingNamesAndRejectDisallowedValues() async throws {
    let modified = _AnyTransferRepresentation<String>(
      exportedContentTypes: [.plainText, .plainText],
      importedContentTypes: [.plainText, .plainText],
      exporting: { value in
        SwiftUIWebTransferPayload(
          data: Data(value.utf8),
          contentType: .plainText,
          suggestedFileName: value == "already named" ? "original.txt" : nil
        )
      },
      importing: { payload in String(decoding: payload.data, as: UTF8.self) }
    )
      .visibility(.ownProcess)
      .exportingCondition { $0 != "blocked" }
      .suggestedFileName { "\($0).txt" }
    let representation = _AnyTransferRepresentation(modified)

    _expectEqual(representation.exportedContentTypes, [.plainText])
    _expectEqual(representation.importedContentTypes, [.plainText])
    _expectTrue(representation.hasExportRepresentation)
    let renamed = try await representation.export("hello")
    _expectEqual(renamed.suggestedFileName, "hello.txt")
    let preserved = try await representation.export("already named")
    _expectEqual(preserved.suggestedFileName, "original.txt")

    do {
      _ = try await representation.export("blocked")
      _fail("An export condition must reject the value")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    }
  }

  @Test
  func exportSelectionFallsBackAndExportAllDeduplicatesActualPayloadTypes() async throws {
    let failing = _AnyTransferRepresentation<String>(
      exportedContentTypes: [.json],
      exporting: { _ in throw TransferContractFailure.export }
    )
    let plainText = _AnyTransferRepresentation<String>(
      exportedContentTypes: [.plainText],
      exporting: { value in
        SwiftUIWebTransferPayload(data: Data(value.utf8), contentType: .plainText)
      }
    )
    let json = _AnyTransferRepresentation<String>(
      exportedContentTypes: [.json],
      exporting: { value in
        SwiftUIWebTransferPayload(data: Data(value.utf8), contentType: .json)
      }
    )
    let representation = TupleTransferRepresentation<String, Void>([failing, plainText, json])._swiftUIWebErased()

    let preferred = try await representation.export("hello", preferred: .plainText)
    _expectEqual(preferred.contentType, .plainText)
    let payloads = try await representation.exportAll(
      "hello",
      preferredContentTypes: [.plainText, .json, .plainText]
    )
    _expectEqual(payloads.map(\.contentType), [.plainText, .json])
    let fallback = try await representation.exportAll("hello", preferredContentTypes: [])
    _expectEqual(fallback.count, 1)
    _expectEqual(fallback.first?.contentType, .plainText)

    let noExporter = _AnyTransferRepresentation<String>.unavailable
    _expectFalse(noExporter.hasExportRepresentation)
    do {
      _ = try await noExporter.export("hello")
      _fail("An empty representation has no exporter")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    }
  }

  @Test
  func importsUseConformanceWildcardAndFallbackErrors() async throws {
    let failedImporter = _AnyTransferRepresentation<String>(
      importedContentTypes: [.text],
      importing: { _ in throw TransferContractFailure.importValue }
    )
    let fallbackImporter = _AnyTransferRepresentation<String>(
      importedContentTypes: [.data],
      importing: { payload in "fallback:\(String(decoding: payload.data, as: UTF8.self))" }
    )
    let representation = TupleTransferRepresentation<String, Void>([failedImporter, fallbackImporter])._swiftUIWebErased()
    let payload = SwiftUIWebTransferPayload(data: Data("hello".utf8), contentType: .plainText)
    let importedFallback = try await representation.import(payload)
    _expectEqual(importedFallback, "fallback:hello")

    let childType = UTType(importedAs: "org.example.markdown", conformingTo: .plainText)
    let childImporter = _AnyTransferRepresentation<String>(
      importedContentTypes: [childType],
      importing: { _ in "child" }
    )
    let childPayload = SwiftUIWebTransferPayload(data: Data(), contentType: .plainText)
    let importedChild = try await childImporter.import(childPayload)
    _expectEqual(importedChild, "child")

    let unsupported = _AnyTransferRepresentation<String>(
      importedContentTypes: [.image],
      importing: { _ in "unreachable" }
    )
    do {
      _ = try await unsupported.import(payload)
      _fail("An incompatible content type must be rejected")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unsupportedContentType)
    }

    let allFail = _AnyTransferRepresentation<String>(
      importedContentTypes: [.plainText],
      importing: { _ in throw TransferContractFailure.importValue }
    )
    do {
      _ = try await allFail.import(payload)
      _fail("The final importer error should be propagated")
    } catch let error as TransferContractFailure {
      _expectEqual(error, .importValue)
    }
  }

  @Test
  func fileRepresentationRetainsNamesTypesAndInPlaceImportPolicy() async throws {
    let representation = FileRepresentation<String>(
      contentType: .plainText,
      shouldAttemptToOpenInPlace: true,
      exporting: { value in
        SentTransferredFile(SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(
          data: Data(value.utf8),
          contentType: .data,
          suggestedFileName: "message.txt"
        )), allowAccessingOriginalFile: true)
      },
      importing: { file in
        let loaded = try await SwiftUIWebFileRuntime.load(file.file)
        return "\(file.isOriginalFile):\(String(decoding: loaded?.data ?? Data(), as: UTF8.self))"
      }
    )
    let erased = _AnyTransferRepresentation<String>(representation)
    let exported = try await erased.export("hello")
    _expectEqual(exported.contentType, .plainText)
    _expectEqual(exported.suggestedFileName, "message.txt")
    let importedFile = try await erased.import(exported)
    _expectEqual(importedFile, "true:hello")

    let importOnly = FileRepresentation<String>(importedContentType: .plainText) { file in
      let loaded = try await SwiftUIWebFileRuntime.load(file.file)
      return String(decoding: loaded?.data ?? Data(), as: UTF8.self)
    }
    _expectTrue(importOnly.shouldAttemptToOpenInPlace == false)
    let importOnlyErased = _AnyTransferRepresentation<String>(importOnly)
    _expectFalse(importOnlyErased.hasExportRepresentation)
    let importedReadOnlyFile = try await importOnlyErased.import(exported)
    _expectEqual(importedReadOnlyFile, "hello")

    let exportOnly = FileRepresentation<String>(
      exportedContentType: .plainText,
      shouldAllowToOpenInPlace: true
    ) { value in
      SentTransferredFile(SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(data: Data(value.utf8), contentType: .plainText)))
    }
    _expectTrue(exportOnly.shouldAllowToOpenInPlace)
    _expectFalse(exportOnly.shouldAttemptToOpenInPlace)
  }

  @Test
  func erasedRepresentationsValidateDynamicTypesAndProxyTransferRoundTrips() async throws {
    let anyRepresentation = SwiftUIWebAnyTransferRepresentation(WrappedTransferValue.transferRepresentation)
    let wrapped = WrappedTransferValue(text: "proxy value")
    let payload = try await anyRepresentation.export(wrapped)
    _expectEqual(payload.contentType, .plainText)
    let importedWrapped = try await anyRepresentation.import(payload, as: WrappedTransferValue.self)
    _expectEqual(importedWrapped, wrapped)

    do {
      _ = try await anyRepresentation.export(42)
      _fail("A mismatched erased value must fail before invoking the exporter")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .invalidData)
    }

    do {
      _ = try await anyRepresentation.import(payload, as: Int.self)
      _fail("A mismatched erased importer result must fail")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .invalidData)
    }
  }

  @Test
  func legacyTransferableDefaultsAndNativeFileAdaptersRemainCompatible() async throws {
    let imported = try await LegacyTransferValue.importing(
      data: Data("legacy".utf8),
      contentType: .plainText
    )
    _expectEqual(imported, LegacyTransferValue(value: "legacy"))
    _expectEqual(LegacyTransferValue.importedContentTypes(), [.plainText])
    do {
      _ = try await LegacyTransferValue(value: "no export").exported(as: nil)
      _fail("Legacy importer-only transferables must not invent an exporter")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftuiweb-transfer-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Foundation.Data("native file".utf8).write(to: url)
    let sent = SentTransferredFile(url, allowAccessingOriginalFile: true)
    let received = ReceivedTransferredFile(file: url, isOriginalFile: true)
    let loadedSent = try await SwiftUIWebFileRuntime.load(sent.file)
    let loadedReceived = try await SwiftUIWebFileRuntime.load(received.file)
    let sentFile = try _require(loadedSent)
    let receivedFile = try _require(loadedReceived)
    _expectEqual(String(decoding: sentFile.data, as: UTF8.self), "native file")
    _expectEqual(String(decoding: receivedFile.data, as: UTF8.self), "native file")
    _expectEqual(sentFile.suggestedFileName, url.lastPathComponent)
    _expectTrue(sent.allowAccessingOriginalFile)
    _expectTrue(received.isOriginalFile)

    let absentURL = url.appendingPathExtension("missing")
    let absent = try? await SwiftUIWebFileRuntime.load(absentURL)
    _expectTrue(absent == nil)
  }

  @Test
  func codableRepresentationSupportsCallerStrategiesAndStandardTypeOverloads() async throws {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let configured = CodableRepresentation<CodableTransferValue, JSONEncoder, JSONDecoder>(
      for: CodableTransferValue.self,
      contentType: .json,
      encoder: encoder,
      decoder: decoder
    )
    let value = CodableTransferValue(displayName: "hello")
    let payload = try await _AnyTransferRepresentation<CodableTransferValue>(configured).export(value)
    _expectTrue(String(decoding: payload.data, as: UTF8.self).contains("display_name"))
    let configuredImport = try await _AnyTransferRepresentation<CodableTransferValue>(configured).import(payload)
    _expectEqual(configuredImport, value)

    let standardTypes = CodableRepresentation<CodableTransferValue, JSONEncoder, JSONDecoder>(
      for: CodableTransferValue.self,
      contentType: .json
    )
    let standard = _AnyTransferRepresentation<CodableTransferValue>(standardTypes)
    let standardPayload = try await standard.export(value)
    let standardImport = try await standard.import(standardPayload)
    _expectEqual(standardImport, value)
  }

  @Test
  func transferRuntimeMaterializesOnceEnrichesMetadataAndCleansOnRemoval() async throws {
    let identifier = "transfer-contract-\(UUID().uuidString)"
    let counter = LockedTransferCounter()
    let cleanup = LockedTransferCounter()
    let expectedData = Data("lazy bytes".utf8)
    SwiftUIWebTransferRuntime.register(
      identifier: identifier,
      metadata: SwiftUIWebTransferMetadata(contentTypes: [], suggestedFileName: "lazy.txt"),
      loader: { _ in
        counter.increment()
        return SwiftUIWebTransferPayload(data: expectedData, contentType: .plainText)
      },
      cleanup: { cleanup.increment() }
    )

    let first = try await SwiftUIWebTransferRuntime.load(identifier: identifier)
    let second = try await SwiftUIWebTransferRuntime.load(identifier: identifier)
    _expectEqual(first?.suggestedFileName, "lazy.txt")
    _expectEqual(second, first)
    _expectEqual(counter.value, 1)
    _expectEqual(SwiftUIWebTransferRuntime.metadata(for: identifier), SwiftUIWebTransferMetadata(
      contentTypes: [.plainText],
      suggestedFileName: "lazy.txt",
      size: Int64(expectedData.count)
    ))

    SwiftUIWebTransferRuntime.remove(identifier: identifier)
    SwiftUIWebTransferRuntime.remove(identifier: identifier)
    _expectEqual(cleanup.value, 1)
    _expectNil(SwiftUIWebTransferRuntime.metadata(for: identifier))
    let removedLoad = try await SwiftUIWebTransferRuntime.load(identifier: identifier)
    _expectNil(removedLoad)
  }

  @Test
  func transferLeaseGenerationProtectsReplacementAndRemoveIfUnleased() {
    let identifier = "transfer-lease-contract-\(UUID().uuidString)"
    let previousCleanup = LockedTransferCounter()
    let replacementCleanup = LockedTransferCounter()
    SwiftUIWebTransferRuntime.register(
      identifier: identifier,
      payload: SwiftUIWebTransferPayload(data: Data("old".utf8), contentType: .plainText),
      cleanup: { previousCleanup.increment() }
    )
    var lease: SwiftUIWebTransferLease? = SwiftUIWebTransferItem(identifier: identifier).lease()
    _expectNotNil(lease)
    SwiftUIWebTransferRuntime.removeIfUnleased(identifier: identifier)
    _expectNotNil(SwiftUIWebTransferRuntime.metadata(for: identifier))

    SwiftUIWebTransferRuntime.register(
      identifier: identifier,
      payload: SwiftUIWebTransferPayload(data: Data("new".utf8), contentType: .json),
      cleanup: { replacementCleanup.increment() }
    )
    _expectEqual(previousCleanup.value, 1)
    lease = nil
    _expectEqual(SwiftUIWebTransferRuntime.metadata(for: identifier)?.contentTypes, [.json])
    _expectEqual(replacementCleanup.value, 0)

    SwiftUIWebTransferRuntime.removeIfUnleased(identifier: identifier)
    _expectNil(SwiftUIWebTransferRuntime.metadata(for: identifier))
    _expectEqual(replacementCleanup.value, 1)
  }

  @Test
  func transferRuntimeCoalescesConcurrentLoadsAndRetriesFailures() async throws {
    let identifier = "transfer-concurrent-contract-\(UUID().uuidString)"
    let counter = LockedTransferCounter()
    let payload = SwiftUIWebTransferPayload(data: Data("once".utf8), contentType: .plainText)
    SwiftUIWebTransferRuntime.register(
      identifier: identifier,
      metadata: SwiftUIWebTransferMetadata(contentType: .plainText),
      loader: { _ in
        counter.increment()
        try await Task.sleep(nanoseconds: 20_000_000)
        return payload
      }
    )

    async let first = SwiftUIWebTransferRuntime.load(identifier: identifier)
    async let second = SwiftUIWebTransferRuntime.load(identifier: identifier)
    let (firstPayload, secondPayload) = try await (first, second)
    _expectEqual(firstPayload, payload)
    _expectEqual(secondPayload, payload)
    _expectEqual(counter.value, 1)
    SwiftUIWebTransferRuntime.remove(identifier: identifier)

    let failedIdentifier = "transfer-retry-contract-\(UUID().uuidString)"
    let failureCounter = LockedTransferCounter()
    SwiftUIWebTransferRuntime.register(
      identifier: failedIdentifier,
      metadata: SwiftUIWebTransferMetadata(contentType: .plainText),
      loader: { _ in
        failureCounter.increment()
        throw TransferContractFailure.export
      }
    )
    for _ in 0..<2 {
      do {
        _ = try await SwiftUIWebTransferRuntime.load(identifier: failedIdentifier)
        _fail("The loader error should propagate")
      } catch let error as TransferContractFailure {
        _expectEqual(error, .export)
      }
    }
    _expectEqual(failureCounter.value, 2)
    SwiftUIWebTransferRuntime.remove(identifier: failedIdentifier)
  }
}

private final class LockedTransferCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func increment() {
    lock.lock()
    storage += 1
    lock.unlock()
  }
}
