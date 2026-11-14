import Testing
import Foundation
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber


// Native builds pass Foundation's NSItemProvider through the drag and drop API, as SwiftUI does. These tests drive
// those providers through their registered representations, which load asynchronously.

// Embedded-only item-provider contract. Foundation builds use the NSItemProvider tests above.

@Suite(.processGlobalState)
@MainActor
final class DragDropTests {
  private struct Card: Codable, Transferable, Equatable {
    let id: Int
    let title: String
    static var transferRepresentation: some TransferRepresentation {
      CodableRepresentation(for: Card.self, contentType: .json)
    }
  }

  @Test
  func aRegisteredDataRepresentationIsWhatTheDragExports() async throws {
    let view = Text("Card").onDrag {
      let provider = NSItemProvider()
      provider.registerDataRepresentation(forTypeIdentifier: "public.plain-text", visibility: .all) { completion in
        completion(Data("hello".utf8), nil)
        return nil
      }
      return provider
    }
    let payloads = try await FiberTree(view).renderNode._dragSource?.export() ?? []
    _expectEqual(payloads.map(\.contentType), [.plainText])
    _expectEqual(payloads.first?.data, Data("hello".utf8))
  }

  @Test
  func aProviderAnswersWhetherItHasATypeConformingToAnother() {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: "public.utf8-plain-text", visibility: .ownProcess) { _ in nil }
    #expect(provider.registeredTypeIdentifiers == ["public.utf8-plain-text"])
    #expect(provider.hasItemConformingToTypeIdentifier("public.utf8-plain-text"))
    #expect(provider.hasItemConformingToTypeIdentifier("public.plain-text"))
    #expect(!provider.hasItemConformingToTypeIdentifier("public.image"))
    // A copy is the same provider, as Foundation's class is.
    let copy = provider
    #expect(copy == provider)
    #expect(NSItemProvider() != NSItemProvider())
  }

  @Test
  func testLegacyDragSourceEmitsStableBrowserNeutralMetadata() async throws {
    let view = Text("Card").onDrag { .text("card-1") }
    let node = FiberTree(view).renderNode
    _expectEqual(node.attributes["draggable"], "true")
    _expectEqual(node.attributes["data-drag-source"], "true")
    _expectEqual(node._dragSource?.preferredTypes, [])
    let payloads = try await node._dragSource?.export() ?? []
    _expectEqual(payloads.first?.contentType, .utf8PlainText)
  }

  @Test
  func testBytePayloadDragOverloadCompiles() async throws {
    let node = FiberTree(Text("Bytes").draggable(Data("bytes".utf8))).renderNode
    let payload = try await node._dragSource?.export().first
    _expectEqual(payload?.data, Data("bytes".utf8))
  }

  @Test
  func previewOverloadsKeepTheHostPreviewOutOfTheSwiftRenderTree() {
    let legacyNode = FiberTree(Text("Legacy").onDrag({ .text("legacy") }, preview: {
      Text("native preview hint")
    })).renderNode

    let transferableNode = FiberTree(Text("Modern").draggable("modern", preview: {
      Text("native preview hint")
    })).renderNode

    #expect(legacyNode.attributes["draggable"] == "true")
    #expect(legacyNode._dragSource?.synchronousExport?().first?.data == Data("legacy".utf8))
    #expect(transferableNode.attributes["draggable"] == "true")
    #expect(transferableNode._dragSource?.preferredTypes == [UTType.utf8PlainText])
    #expect(!legacyNode.htmlDescription.contains("native preview hint"))
    #expect(!transferableNode.htmlDescription.contains("native preview hint"))
  }

  @Test
  func modernDraggableWithoutPreviewExportsItsTransferableValue() async throws {
    let node = FiberTree(Text("Modern").draggable("plain modern source")).renderNode

    #expect(node.attributes["draggable"] == "true")
    #expect(node._dragSource?.preferredTypes == [.utf8PlainText])
    let payload = try await node._dragSource?.export().first
    #expect(payload?.contentType == .utf8PlainText)
    #expect(payload?.data == Data("plain modern source".utf8))
  }

  @Test
  func testTransferableSourceDefersExportAndAdvertisesRepresentations() {
    let card = Card(id: 4, title: "Inbox")
    let node = FiberTree(Text("Card").draggable(card)).renderNode
    _expectEqual(node._dragSource?.preferredTypes, [.json])
    _expectNotNil(node._dragSource)
  }

  @Test
  func testURLIsTransferableForExternalURLDrops() async throws {
    let value = try _require(URL(string: "https://swift.org/docs"))
    let payload = try await value._swiftUIWebExport()
    _expectEqual(payload.contentType, .url)
    let restored = try await URL.importing(data: payload.data, contentType: .url)
    _expectEqual(restored.absoluteString, value.absoluteString)
  }

  @Test
  func testLegacyDropTargetStoresAcceptedTypesAndTargetBinding() {
    var targeted = false
    let view = Text("Drop").onDrop(of: [.plainText, .url], isTargeted: Binding(get: { targeted }, set: { targeted = $0 })) { providers in
      !providers.isEmpty
    }
    let node = FiberTree(view).renderNode
    _expectEqual(node.attributes["data-drop-target"], "true")
    _expectEqual(node.attributes["data-drop-types"], "public.plain-text,public.url")
    _expectNotNil(node._dropTarget)
    node._dropTarget?.targeted?(true)
    _expectTrue(targeted)
  }

  @Test
  func testStaticRendererKeepsDragDropSemanticsWithoutBrowserObjects() {
    let html = StaticHTMLFiberRenderer().render(
      HStack {
        Text("Drag").onDrag { .text("hello") }
        Text("Drop").onDrop(of: [], isTargeted: nil, perform: { _ in true })
      }
    )
    _expectTrue(html.contains("draggable=\"true\""))
    _expectTrue(html.contains("data-drag-source=\"true\""))
    _expectTrue(html.contains("data-drop-target=\"true\""))
  }

  @Test
  func testDropDestinationLoadsTransferableAndPreservesLocation() async throws {
    let payload = SwiftUIWebTransferPayload(data: Data("hello".utf8), contentType: .utf8PlainText)
    let provider = NSItemProvider(payload: payload)
    let expectation = _makeExpectation(description: "destination action")
    var received: [String] = []
    var point = CGPoint(x: 0, y: 0)
    let view = Text("Drop").dropDestination(for: String.self, action: { values, location in
      received = values
      point = location
      expectation.fulfill()
      return true
    }, isTargeted: { _ in })
    let node = FiberTree(view).renderNode
    _expectEqual(node._dropTarget?.acceptedTypes, [.utf8PlainText])
    _expectTrue(node._dropTarget?.perform([provider], DropInfo(location: CGPoint(x: 12, y: 24), types: [.plainText])) == true)
    await _fulfillment(of: [expectation], timeout: 1)
    _expectEqual(received, ["hello"])
    _expectEqual(point.x, 12)
    _expectEqual(point.y, 24)
  }

  @Test
  func testDropInfoFiltersLazyProvidersByUniformType() {
    let text = NSItemProvider(payload: SwiftUIWebTransferPayload(data: Data("x".utf8), contentType: .plainText))
    let url = NSItemProvider(payload: SwiftUIWebTransferPayload(data: Data("https://swift.org".utf8), contentType: .url))
    let info = DropInfo(location: CGPoint(x: 1, y: 2), types: [.plainText, .url], providers: [text, url])
    _expectTrue(info.hasItemsConforming(to: [.text]))
    _expectEqual(info.itemProviders(for: [.url]).count, 1)
    _expectEqual(info.itemProviders(for: []).count, 2)
  }

  @Test
  func testDropProviderLeasesReleaseRuntimePayload() async throws {
    let payload = SwiftUIWebTransferPayload(data: Data([1, 2, 3]), contentType: .data)
    var provider = Optional(NSItemProvider(payload: payload))
    guard let id = provider?._identifier else { return _fail("provider should be created") }
    _expectNotNil(SwiftUIWebTransferRuntime.metadata(for: id))
    let loaded = try await provider!.loadData()
    _expectEqual(loaded.count, 3)
    provider = nil
    _expectNil(SwiftUIWebTransferRuntime.metadata(for: id))
  }

  @Test
  func immediateDropTextAndDragStartCallbackAreAvailableDuringTheirEvents() {
    let plainText = NSItemProvider(payload: SwiftUIWebTransferPayload(
      data: Data("item-42".utf8), contentType: .plainText
    ))
    #expect(plainText.plainTextValue == "item-42")

    let binary = NSItemProvider(payload: SwiftUIWebTransferPayload(
      data: Data([0, 1, 2]), contentType: .data
    ))
    #expect(binary.plainTextValue == nil)

    var starts = 0
    let node = FiberTree(Text("Start drag").onDrag("item-42", onStarted: { starts += 1 })).renderNode
    #expect(node._dragSource?.onStarted != nil)
    node._dragSource?.onStarted?()
    #expect(starts == 1)
  }

  @Test
  func expiredDropProviderReportsUnavailableInsteadOfReturningEmptyBytes() async throws {
    let provider = NSItemProvider(
      identifier: "expired-drop-item-\(UUID().uuidString)",
      metadata: SwiftUIWebTransferMetadata(contentType: .plainText, size: 4)
    )

    do {
      _ = try await provider.loadData()
      Issue.record("An expired browser drop item must not masquerade as an empty payload")
    } catch let error as SwiftUIWebTransferError {
      #expect(error.code == .unavailable)
    }
  }

  @Test
  func testDragPayloadConveniencesAndDropProviderValueSemantics() async throws {
    let text = NSItemProvider.text("plain text")
    _expectEqual(text.payloads.first?.contentType, .utf8PlainText)
    _expectEqual(text.payloads.first?.data, Data("plain text".utf8))

    let urlProvider = NSItemProvider.url("https://swift.org")
    _expectEqual(urlProvider.payloads.first?.contentType, .url)
    _expectEqual(urlProvider.payloads.first?.suggestedFileName, nil)

    let fileProvider = NSItemProvider.file(
      Data([0, 1, 255]), contentType: .data, suggestedFileName: "archive.bin"
    )
    _expectEqual(fileProvider.payloads.first?.contentType, .data)
    _expectEqual(fileProvider.payloads.first?.suggestedFileName, "archive.bin")
    _expectEqual(NSItemProvider(payloads: [text.payloads[0], fileProvider.payloads[0]]).payloads.count, 2)

    let metadata = SwiftUIWebTransferMetadata(contentType: .plainText, suggestedFileName: "note.txt", size: 4)
    let first = NSItemProvider(identifier: "shared-id", metadata: metadata)
    let equal = NSItemProvider(identifier: "shared-id", metadata: metadata)
    let differentIdentifier = NSItemProvider(
      identifier: "different-id", metadata: metadata
    )
    _expectEqual(first, equal)
    _expectNotEqual(first, differentIdentifier)
    _expectEqual(Set([first, equal, differentIdentifier]).count, 2)
    _expectTrue(DropInfo(types: [.plainText]).hasItems)
    _expectFalse(DropInfo().hasItems)
  }

  @Test
  func testURLTransferableConstructionRejectsInvalidTextAndAdvertisesURLTypes() async throws {
    _expectEqual(URL.importedContentTypes(), [.url])
    let decoded = try await URL.importing(
      data: Data("https://swift.org".utf8), contentType: .url
    )
    _expectEqual(decoded.absoluteString, "https://swift.org")

    do {
      _ = try await URL.importing(
        data: Data("http://[".utf8), contentType: .url
      )
      Issue.record("The URL transfer representation must reject malformed URL text")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .invalidData)
    }

    do {
      _ = try await URL.importing(data: Data("http://[".utf8), contentType: .url)
      Issue.record("Malformed URL text must not import as a valid URL")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .invalidData)
    }
  }
}
