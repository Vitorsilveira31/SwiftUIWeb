import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Browser) import SwiftUIWebCore
@_spi(Browser) import SwiftUIWebFeatures


// Native builds deliver a paste as a Foundation NSItemProvider whose representations read the transfer runtime. The
// browser's clipboard event is replaced by dispatching the same tokens the browser host sends.

// Embedded-only item-provider contract. Foundation builds use the NSItemProvider tests above.

@Suite(.processGlobalState)
@MainActor
final class PasteButtonTests {
  /// Swift 6.4 treats `Task` closures as sending. Keep the asynchronous
  /// provider result in a tiny synchronized box instead of capturing a
  /// mutable local variable across isolation regions.
  private final class LockedValues<Value>: @unchecked Sendable {
    private var storage: [Value] = []
    private let lock = NSLock()

    func append(_ value: Value) {
      lock.lock()
      storage.append(value)
      lock.unlock()
    }

    var values: [Value] {
      lock.lock()
      let copy = storage
      lock.unlock()
      return copy
    }
  }

  private struct Note: Transferable, Equatable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
      DataRepresentation<Note>(
        contentType: .plainText,
        exporting: { Data($0.value.utf8) },
        importing: { Note(value: String(decoding: $0, as: UTF8.self)) }
      )
    }
  }

  private struct UnsupportedPayload: Transferable {
    static var transferRepresentation: _AnyTransferRepresentation<UnsupportedPayload> {
      _AnyTransferRepresentation<UnsupportedPayload>()
    }
  }

  private struct LabelStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
    }
  }

  @Test
  func testSwiftUIInitializersCompile() {
    _ = PasteButton(payloadType: String.self, onPaste: { _ in })
    _ = PasteButton(supportedContentTypes: [.url], payloadAction: { _ in })
    _ = PasteButton(supportedContentTypes: [.url], validator: { _ in "validated" }, payloadAction: { _ in })
  }

  @Test
  func testEmptyLegacyTypesUseDataFallbackAndCustomButtonEnvironmentRenders() throws {
    let tree = FiberTree(
      PasteButton(supportedContentTypes: [], payloadAction: { _ in })
        .buttonStyle(LabelStyle())
        .tint(.red)
    )
    let button = try #require(tree.findNode(withEvent: PasteButtonRuntime.event))
    #expect(button.attributes["data-paste-types"] == "public.data")
    #expect(button.attributes["data-button-style-custom"] == "true")
    #expect(button.attributes["data-tint"] == Color.red.cssValue)
    #expect(button.styles["--tint-color"] == Color.red.cssValue)
    #expect(button.htmlDescription.contains("Paste"))

    let payloadFallback = try #require(findPasteButton(FiberTree(
      PasteButton(payloadType: UnsupportedPayload.self) { _ in }
    ).renderNode))
    #expect(payloadFallback.attributes["data-paste-types"] == "public.data")

    let unknownType = UTType(importedAs: "org.example.unregistered", conformingTo: .data)
    let withoutBrowserFilter = try #require(findPasteButton(FiberTree(
      PasteButton(supportedContentTypes: [unknownType], payloadAction: { _ in })
    ).renderNode))
    #expect(withoutBrowserFilter.attributes["data-paste-accept"] == nil)
  }

  @Test
  func testPayloadTypeRendersClipboardMetadataAndDefaultLabel() {
    let html = StaticHTMLFiberRenderer().render(PasteButton(payloadType: String.self) { _ in })
    _expectTrue(html.contains("<button"))
    _expectTrue(html.contains("paste-button"))
    _expectTrue(html.contains("data-paste-button=\"true\""))
    _expectTrue(html.contains("data-paste-types=\"public.utf8-plain-text\""))
    _expectTrue(html.contains(">Paste</button>"))
    _expectFalse(html.contains("navigator.clipboard"))
    _expectFalse(html.contains("Blob"))
  }

  @Test
  func testTransferablePasteImportsTextAndURL() async throws {
    let textPayload = SwiftUIWebTransferPayload(
      data: Data("hello".utf8),
      contentType: .utf8PlainText
    )
    let textProvider = NSItemProvider(payload: textPayload)
    let textExpectation = _makeExpectation(description: "text pasted")
    var receivedText: [String] = []
    let textTree = FiberTree(PasteButton(payloadType: String.self) { values in
      receivedText = values
      textExpectation.fulfill()
    })
    textTree.dispatch(
      event: PasteButtonRuntime.event,
      value: PasteButtonRuntime.successPrefix + textProvider._identifier
    )
    await _fulfillment(of: [textExpectation], timeout: 1)
    _expectEqual(receivedText, ["hello"])

    let urlPayload = SwiftUIWebTransferPayload(
      data: Data("https://swift.org/docs".utf8),
      contentType: .url
    )
    let urlProvider = NSItemProvider(payload: urlPayload)
    let urlExpectation = _makeExpectation(description: "URL pasted")
    var receivedURL: [URL] = []
    let urlTree = FiberTree(PasteButton(payloadType: URL.self) { values in
      receivedURL = values
      urlExpectation.fulfill()
    })
    urlTree.dispatch(
      event: PasteButtonRuntime.event,
      value: PasteButtonRuntime.successPrefix + urlProvider._identifier
    )
    await _fulfillment(of: [urlExpectation], timeout: 1)
    _expectEqual(receivedURL.first?.absoluteString, "https://swift.org/docs")
  }

  @Test
  func testCustomTransferableUsesRepresentationImporter() async throws {
    let provider = NSItemProvider(payload: SwiftUIWebTransferPayload(
      data: Data("from clipboard".utf8),
      contentType: .plainText
    ))
    let expectation = _makeExpectation(description: "custom type pasted")
    var value: Note?
    let tree = FiberTree(PasteButton(payloadType: Note.self) { values in
      value = values.first
      expectation.fulfill()
    })
    tree.dispatch(
      event: PasteButtonRuntime.event,
      value: PasteButtonRuntime.successPrefix + provider._identifier
    )
    await _fulfillment(of: [expectation], timeout: 1)
    _expectEqual(value, Note(value: "from clipboard"))
  }

  @Test
  func testLegacyProviderCallbackCanLoadDataLazily() async throws {
    let imageHTML = StaticHTMLFiberRenderer().render(
      PasteButton(supportedContentTypes: [.image], payloadAction: { _ in })
    )
    _expectTrue(imageHTML.contains(#"data-paste-types="public.image""#))

    let provider = NSItemProvider(payload: SwiftUIWebTransferPayload(
      data: Data([0, 1, 2, 255]),
      contentType: .png,
      suggestedFileName: "clipboard.png"
    ))
    let expectation = _makeExpectation(description: "provider pasted")
    let received = LockedValues<Data>()
    let tree = FiberTree(PasteButton(supportedContentTypes: [.image], payloadAction: { providers in
      Task {
        if let data = try? await providers[0].loadData() {
          received.append(data)
        }
        expectation.fulfill()
      }
    }))
    tree.dispatch(
      event: PasteButtonRuntime.event,
      value: PasteButtonRuntime.successPrefix + provider._identifier
    )
    await _fulfillment(of: [expectation], timeout: 1)
    _expectEqual(received.values.first, Data([0, 1, 2, 255]))
  }

  @Test
  func testCancellationAndFailureTokensDoNotInvokePasteCallback() async throws {
    var called = false
    let tree = FiberTree(PasteButton(payloadType: String.self) { _ in called = true })
    tree.dispatch(event: PasteButtonRuntime.event, value: PasteButtonRuntime.cancelled)
    tree.dispatch(event: PasteButtonRuntime.event, value: PasteButtonRuntime.failurePrefix + "permission denied")
    try await Task.sleep(nanoseconds: 20_000_000)
    _expectFalse(called)
  }

  @Test
  func testInlineClipboardTextFallbackIsDecodedAndInvalidPayloadIsIgnored() async throws {
    let expectation = _makeExpectation(description: "inline clipboard text imported")
    let received = LockedValues<String>()
    let tree = FiberTree(PasteButton(payloadType: String.self) { values in
      for value in values { received.append(value) }
      expectation.fulfill()
    })

    tree.dispatch(event: PasteButtonRuntime.event, value: "inline-text:aGVsbG8=")
    await _fulfillment(of: [expectation], timeout: 1)
    _expectEqual(received.values, ["hello"])

    var calledForMalformed = false
    let malformed = FiberTree(PasteButton(payloadType: String.self) { _ in calledForMalformed = true })
    malformed.dispatch(event: PasteButtonRuntime.event, value: "inline-text:not base64!")
    malformed.dispatch(event: PasteButtonRuntime.event, value: "success:")
    malformed.dispatch(event: PasteButtonRuntime.event, value: "success:missing-provider")
    try await Task.sleep(nanoseconds: 20_000_000)
    _expectFalse(calledForMalformed)
  }

  @Test
  func testReleasedClipboardProviderReportsUnavailableInsteadOfCrashing() async {
    let provider = NSItemProvider(payload: SwiftUIWebTransferPayload(
      data: Data("temporary".utf8),
      contentType: .plainText
    ))
    SwiftUIWebTransferRuntime.remove(identifier: provider._identifier)
    do {
      _ = try await provider.loadData()
      _fail("A released clipboard item should not be readable")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unavailable)
    } catch {
      _fail("Unexpected transfer error: \(error)")
    }
  }

  @Test
  func testDisabledPasteButtonDoesNotExposeClipboardEvent() {
    let html = StaticHTMLFiberRenderer().render(
      PasteButton(payloadType: String.self) { _ in }.disabled(true)
    )
    _expectTrue(html.contains("disabled=\"disabled\""))
    _expectTrue(html.contains("aria-disabled=\"true\""))
    _expectFalse(html.contains("data-fiber-event-id"))
  }

  private func findPasteButton(_ node: _RenderNode) -> _RenderNode? {
    if node.attributes["data-control-kind"] == "paste-button" { return node }
    for child in node.children {
      if let match = findPasteButton(child) { return match }
    }
    return nil
  }
}
