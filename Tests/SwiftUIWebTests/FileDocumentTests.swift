import Foundation
import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Browser) @_spi(Renderer) import SwiftUIWebCore
@_spi(Browser) @_spi(Renderer) import SwiftUIWebFeatures

private struct TestTextDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }
  static var writableContentTypes: [UTType] { [.plainText] }
  var text: String

  init(text: String = "") { self.text = text }

  init(configuration: FileDocumentReadConfiguration) throws {
    guard let bytes = configuration.file.regularFileContents else {
      throw SwiftUIWebTransferError(.invalidData, message: "Missing regular file contents")
    }
    text = String(decoding: bytes, as: UTF8.self)
  }

  func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

private struct DirectoryDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  var text: String = ""

  init() {}

  init(configuration: FileDocumentReadConfiguration) throws {
    text = "directory"
  }

  func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
    FileWrapper(directoryWithFileWrappers: [:])
  }
}

private struct ThrowingDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.plainText] }

  init() {}

  init(configuration: FileDocumentReadConfiguration) throws {}

  func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
    throw SwiftUIWebTransferError(.unavailable, message: "document unavailable")
  }
}

@Suite(.processGlobalState)
@MainActor
final class FileDocumentTests {
  @Test
  func testImporterCarriesSelectionPolicyWithoutBrowserMarkup() {
    var presented = false
    let view = Text("Import").fileImporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      allowedContentTypes: [.plainText, .json],
      allowsMultipleSelection: true,
      onCompletion: { _ in }
    )
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("data-file-importer=\"true\""))
    _expectTrue(html.contains("data-file-importer-multiple=\"true\""))
    _expectTrue(html.contains("text/plain"))
    _expectTrue(html.contains("application/json"))
    _expectFalse(html.contains("<input"), "Browser picker inputs are host-created, never public render output.")
  }

  @Test
  func testImporterSelectionMapsOpaqueURLsAndDismissesPresentation() {
    var presented = true
    var result: Result<[URL], Error>?
    let view = Text("Import").fileImporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      allowedContentTypes: [.plainText],
      allowsMultipleSelection: true,
      onCompletion: { result = $0 }
    )
    let tree = FiberTree(view)
    let node = tree.findNode(withEvent: FileImporterRuntime.event)
    _expectNotNil(node)

    tree.dispatch(
      event: FileImporterRuntime.event,
      value: "\(FileImporterRuntime.successPrefix)file-a,file-b",
      on: node
    )
    _expectEqual(result?.successValue?.map(\.absoluteString), [
      "transfer-file://file-a", "transfer-file://file-b"
    ])
    _expectFalse(presented)
  }

  @Test
  func testImporterCancellationIsReportedAndDismissesPresentation() {
    var presented = true
    var result: Result<[URL], Error>?
    let view = Text("Import").fileImporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      allowedContentTypes: [.data],
      allowsMultipleSelection: true,
      onCompletion: { result = $0 }
    )
    let tree = FiberTree(view)
    let node = tree.findNode(withEvent: FileImporterRuntime.event)
    tree.dispatch(event: FileImporterRuntime.event, value: FileImporterRuntime.cancelled, on: node)
    let error = result?.failureValue as? SwiftUIWebTransferError
    _expectEqual(error?.code, .cancelled)
    _expectFalse(presented)
  }

  @Test
  func testFileRuntimeLoadsSelectedPayloadAndDocument() async throws {
    _expectEqual(DirectoryDocument.writableContentTypes, DirectoryDocument.readableContentTypes)
    SwiftUIWebTransferRuntime.register(
      identifier: "selected",
      payload: SwiftUIWebTransferPayload(
        data: Data("hello".utf8),
        contentType: .plainText,
        suggestedFileName: "hello.txt"
      )
    )
    let url = SwiftUIWebFileRuntime.url(identifier: "selected")
    let loadedFile = try await SwiftUIWebFileRuntime.load(url)
    let file = try _require(loadedFile)
    _expectEqual(file.data, Data("hello".utf8))
    _expectEqual(file.suggestedFileName, "hello.txt")
    let loadedDocument = try await SwiftUIWebFileRuntime.load(TestTextDocument.self, from: url)
    let document = try _require(loadedDocument)
    _expectEqual(document.text, "hello")
    let loadedText = try await SwiftUIWebFileRuntime.loadTransferable(String.self, from: url)
    _expectEqual(loadedText, "hello")
    SwiftUIWebTransferRuntime.remove(identifier: "selected")
  }

  @Test
  func testExporterRegistersDocumentProviderAndReportsURL() async throws {
    var presented = true
    var result: Result<URL, Error>?
    let view = Text("Export").fileExporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      document: TestTextDocument(text: "exported"),
      contentType: .plainText,
      defaultFilename: "result.txt",
      onCompletion: { result = $0 }
    )
    let tree = FiberTree(view)
    let node = try _require(tree.findNode(withEvent: FileExporterRuntime.event))
    let key = try _require(node.attributes["data-file-exporter-key"])
    let payload = try await FileExporterRuntime.export(key: key)
    _expectEqual(payload.data, Data("exported".utf8))
    _expectEqual(payload.suggestedFileName, "result.txt")

    tree.dispatch(event: FileExporterRuntime.event, value: "\(FileExporterRuntime.successPrefix)exported-id", on: node)
    _expectEqual(result?.successValue?.absoluteString, "transfer-file://exported-id")
    _expectFalse(presented)
  }

  @Test
  func testExporterCancellationCallbackRuns() {
    var presented = true
    var cancelled = false
    let view = Text("Export").fileExporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      document: TestTextDocument(text: "exported"),
      contentType: .plainText,
      onCompletion: { _ in },
      onCancellation: { cancelled = true }
    )
    let tree = FiberTree(view)
    let node = tree.findNode(withEvent: FileExporterRuntime.event)
    tree.dispatch(event: FileExporterRuntime.event, value: FileExporterRuntime.cancelled, on: node)
    _expectTrue(cancelled)
    _expectFalse(presented)
  }

  @Test
  func testExporterCompletionSpellingReportsHostFailureAndDismisses() throws {
    var presented = true
    var result: Result<URL, Error>?
    let view = Text("Export")
      .fileExporter(
        isPresented: Binding(get: { presented }, set: { presented = $0 }),
        document: TestTextDocument(text: "exported"),
        contentType: .plainText,
        onCompletion: { result = $0 }
      )
    let tree = FiberTree(view)
    let node = try _require(tree.findNode(withEvent: FileExporterRuntime.event))

    tree.dispatch(event: FileExporterRuntime.event, value: "error:host denied", on: node)

    let error = result?.failureValue as? SwiftUIWebTransferError
    _expectEqual(error?.code, .unavailable)
    _expectEqual(error?.message, "host denied")
    _expectFalse(presented)
  }

  @Test
  func testImporterDecodesInlinePayloadAndReportsMalformedOrRejectedInput() async throws {
    var presented = true
    var results: [Result<[URL], Error>] = []
    let view = Text("Import").fileImporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      allowedContentTypes: [.plainText],
      allowsMultipleSelection: true,
      onCompletion: { results.append($0) }
    )
    let tree = FiberTree(view)
    let node = try _require(tree.findNode(withEvent: FileImporterRuntime.event))

    tree.dispatch(
      event: FileImporterRuntime.event,
      value: "success-inline:text/plain:notes.txt:aGVsbG8=",
      on: node
    )
    let importedURL = try _require(results[0].successValue?.first)
    let importedResultFile = try await SwiftUIWebFileRuntime.load(importedURL)
    let importedFile = try _require(importedResultFile)
    _expectEqual(importedFile.data, Data("hello".utf8))
    _expectEqual(importedFile.contentType, .plainText)
    _expectEqual(importedFile.suggestedFileName, "notes.txt")
    _expectFalse(presented)

    presented = true
    tree.dispatch(event: FileImporterRuntime.event, value: "success-inline:text/plain", on: node)
    _expectEqual(results[1].failureValue as? SwiftUIWebTransferError, SwiftUIWebTransferError(.invalidData, message: "Invalid embedded file payload"))
    _expectFalse(presented)

    presented = true
    tree.dispatch(event: FileImporterRuntime.event, value: "error:picker denied", on: node)
    let error = results[2].failureValue as? SwiftUIWebTransferError
    _expectEqual(error?.code, .unavailable)
    _expectEqual(error?.message, "picker denied")
    _expectFalse(presented)

    presented = true
    tree.dispatch(
      event: FileImporterRuntime.event,
      value: "success-inline:text/plain:invalid.txt:%%%",
      on: node
    )
    _expectEqual((results[3].failureValue as? SwiftUIWebTransferError)?.code, .invalidData)
    _expectFalse(presented)
  }

  @Test
  func testExporterInlinePayloadAndProviderFailuresHaveObservableResults() async throws {
    var presented = true
    var results: [Result<URL, Error>] = []
    let inlineView = Text("Export").fileExporter(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      document: TestTextDocument(text: "inline bytes"),
      contentType: .plainText,
      defaultFilename: "inline.txt",
      onCompletion: { results.append($0) },
      onCancellation: {}
    )
    let inlineTree = FiberTree(inlineView)
    let inlineNode = try _require(inlineTree.findNode(withEvent: FileExporterRuntime.event))
    inlineTree.dispatch(
      event: FileExporterRuntime.event,
      value: "success-inline:text/plain:inline.txt:aW5saW5lIGJ5dGVz",
      on: inlineNode
    )
    let exportedURL = try _require(results[0].successValue)
    let exportedResultFile = try await SwiftUIWebFileRuntime.load(exportedURL)
    let exportedFile = try _require(exportedResultFile)
    _expectEqual(exportedFile.data, Data("inline bytes".utf8))
    _expectEqual(exportedFile.suggestedFileName, "inline.txt")
    _expectFalse(presented)

    presented = true
    inlineTree.dispatch(event: FileExporterRuntime.event, value: "success-inline:text/plain", on: inlineNode)
    _expectEqual((results[1].failureValue as? SwiftUIWebTransferError)?.code, .invalidData)
    _expectFalse(presented)

    presented = true
    inlineTree.dispatch(
      event: FileExporterRuntime.event,
      value: "success-inline:text/plain:invalid.txt:%%%",
      on: inlineNode
    )
    _expectEqual((results[2].failureValue as? SwiftUIWebTransferError)?.code, .invalidData)
    _expectFalse(presented)

    let directoryView = Text("Export directory").fileExporter(
      isPresented: .constant(false),
      document: DirectoryDocument(),
      contentType: .data,
      onCompletion: { _ in }
    )
    let directoryNode = FiberTree(directoryView).renderNode
    let directoryKey = try _require(directoryNode.attributes["data-file-exporter-key"])
    do {
      _ = try await FileExporterRuntime.export(key: directoryKey)
      Issue.record("Directory documents must not be exported as regular files")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .invalidData)
    }

    let throwingView = Text("Export failure").fileExporter(
      isPresented: .constant(false),
      document: ThrowingDocument(),
      contentType: .plainText,
      onCompletion: { _ in }
    )
    let throwingKey = try _require(FiberTree(throwingView).renderNode.attributes["data-file-exporter-key"])
    do {
      _ = try await FileExporterRuntime.export(key: throwingKey)
      Issue.record("Document writer failures must propagate from the provider")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.message, "document unavailable")
    }

    do {
      _ = try await FileExporterRuntime.export(key: "removed-provider")
      Issue.record("Missing exporter providers must be reported")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    }
    FileExporterRuntime.remove(key: directoryKey)
    FileExporterRuntime.remove(key: throwingKey)
    FileExporterRuntime.remove(key: inlineNode.attributes["data-file-exporter-key"] ?? "")
  }

  @Test
  func testOpaqueURLsAndNativeFileLoadingFallback() async throws {
    let emptyIdentifierURL = SwiftUIWebFileRuntime.url(identifier: "")
    _expectNil(SwiftUIWebFileRuntime.identifier(from: emptyIdentifierURL))
    _expectNil(SwiftUIWebFileRuntime.identifier(from: URL(string: "https://example.test/file.txt")!))

    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftuiweb-document-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: path) }
    try Data("native file".utf8).write(to: path)

    let loadedFile = try await SwiftUIWebFileRuntime.load(path)
    let file = try _require(loadedFile)
    _expectEqual(file.data, Data("native file".utf8))
    _expectEqual(file.contentType, .plainText)
    _expectEqual(file.suggestedFileName, path.lastPathComponent)
    let loadedData = try await SwiftUIWebFileRuntime.loadData(path)
    _expectEqual(loadedData, Data("native file".utf8))
    _expectNil(swiftUIWebFileData(FileWrapper(directoryWithFileWrappers: [:])))
  }

  @Test
  func testMoverPresentsFilesAndReportsMovedAndDownloadedResults() async throws {
    let first = SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(data: Data("one".utf8), contentType: .plainText, suggestedFileName: "one.txt"))
    let second = SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(data: Data("two".utf8), contentType: .data, suggestedFileName: "two.bin"))
    var presented = true
    var results: [Result<[URL], Error>] = []
    var cancellations = 0
    let view = Text("Move").fileMover(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      files: [first, second],
      onCompletion: { results.append($0) },
      onCancellation: { cancellations += 1 }
    )
    let tree = FiberTree(view)
    let node = try _require(tree.findNode(withEvent: FileMoverRuntime.event))
    _expectEqual(node.attributes["data-file-mover-presented"], "true")
    _expectEqual(node.attributes["data-file-mover-count"], "2")
    let records = try _require(node.attributes["data-file-mover-files"]).split(separator: ";")
    _expectEqual(records.count, 2)
    _expectTrue(records[0].hasSuffix(",b25l"))  // base64("one")
    let token = try _require(node.attributes["data-file-mover-token"])

    // A download fallback cannot confirm the move: the originals are reported and stay readable.
    tree.dispatch(event: FileMoverRuntime.event, value: "downloaded:2", on: node)
    _expectEqual(results[0].successValue, [first, second])
    _expectFalse(presented)
    let stillThere = try await SwiftUIWebFileRuntime.load(first)
    _expectNotNil(stillThere)

    // An answer without this request's token (another mover's, or forged) is refused, and the sources stay.
    presented = true
    tree.dispatch(event: FileMoverRuntime.event, value: "moved:tok=0000000000000000;moved-a,bmV3LnR4dA==;moved-b,Yi5iaW4=", on: node)
    _expectEqual((results[1].failureValue as? SwiftUIWebTransferError)?.code, .invalidData)
    results.remove(at: 1)

    // A real move reports the new locations and drops the sources.
    presented = true
    tree.dispatch(event: FileMoverRuntime.event, value: "moved:tok=\(token);moved-a,bmV3LnR4dA==;moved-b,Yi5iaW4=", on: node)
    let moved = try _require(results[1].successValue)
    _expectEqual(moved.map(\.absoluteString), ["transfer-file://moved-a", "transfer-file://moved-b"])
    let movedFileResult = try await SwiftUIWebFileRuntime.load(moved[0])
    let movedFile = try _require(movedFileResult)
    _expectEqual(movedFile.data, Data("one".utf8))
    _expectEqual(movedFile.suggestedFileName, "new.txt")
    let removed = try await SwiftUIWebFileRuntime.load(first)
    _expectNil(removed)
    _expectFalse(presented)

    // Cancellation goes to onCancellation; errors and malformed results are failures.
    presented = true
    tree.dispatch(event: FileMoverRuntime.event, value: "cancelled", on: node)
    _expectEqual(cancellations, 1)
    presented = true
    tree.dispatch(event: FileMoverRuntime.event, value: "error:disk full", on: node)
    _expectEqual((results[2].failureValue as? SwiftUIWebTransferError)?.message, "disk full")
    presented = true
    tree.dispatch(event: FileMoverRuntime.event, value: "moved:only-one,YQ==", on: node)
    _expectEqual((results[3].failureValue as? SwiftUIWebTransferError)?.code, .invalidData)
  }

  @Test
  func testMoverSingleFileWithoutCancellationHandlerAndUnavailableFiles() throws {
    let url = SwiftUIWebFileRuntime.url(for: SwiftUIWebTransferPayload(data: Data("x".utf8), contentType: .plainText, suggestedFileName: "x.txt"))
    var presented = true
    var results: [Result<URL, Error>] = []
    let view = Text("Move").fileMover(isPresented: Binding(get: { presented }, set: { presented = $0 }), file: url) { results.append($0) }
    let tree = FiberTree(view)
    let node = try _require(tree.findNode(withEvent: FileMoverRuntime.event))
    tree.dispatch(event: FileMoverRuntime.event, value: "cancelled", on: node)
    _expectEqual((results[0].failureValue as? SwiftUIWebTransferError)?.code, .cancelled)

    // A native path, or no file, is never handed to the host: bytes are flagged missing / nothing is presented.
    var emptyPresented = true
    let nativeNode = try _require(FiberTree(Text("Move").fileMover(isPresented: Binding(get: { emptyPresented }, set: { emptyPresented = $0 }), file: URL(fileURLWithPath: "/tmp/none.txt")) { _ in }).findNode(withEvent: FileMoverRuntime.event))
    let nativeFiles = try _require(nativeNode.attributes["data-file-mover-files"])
    _expectTrue(nativeFiles.hasSuffix(",-"))
    let emptyNode = try _require(FiberTree(Text("Move").fileMover(isPresented: .constant(true), file: nil) { _ in }).findNode(withEvent: FileMoverRuntime.event))
    _expectEqual(emptyNode.attributes["data-file-mover-presented"], "false")
  }
}

private extension Result {
  var successValue: Success? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  var failureValue: Failure? {
    guard case .failure(let value) = self else { return nil }
    return value
  }
}
