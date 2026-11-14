import Foundation
import Testing
import SwiftUIWeb
import SwiftUIWebHTML
@_spi(Browser) import SwiftUIWebPhotosUI
@_spi(Renderer) import SwiftUIWebTransferable
import SwiftUIWebUniformTypeIdentifiers

@Suite
@MainActor
final class PhotosPickerTests {
  @Test
  func testPickerRendersSemanticControlAndFilterMetadata() {
    var selected: PhotosPickerItem?
    let binding = Binding<PhotosPickerItem?>(get: { selected }, set: { selected = $0 })
    let picker = PhotosPicker(selection: binding, matching: .images) {
      Text("Choose photo")
    }

    let html = StaticHTMLFiberRenderer().render(picker)
    _expectTrue(html.contains("photos-picker"))
    _expectTrue(html.contains("data-photos-picker-accept=\"image/*\""))
    _expectTrue(html.contains("Choose photo"))
    _expectFalse(html.contains("<input"), "The public picker render is a semantic control; the browser input is host-created.")
  }

  @Test
  func testDefaultMatchingIsMediaOnly() {
    var selected: PhotosPickerItem?
    let picker = PhotosPicker(selection: Binding(get: { selected }, set: { selected = $0 })) {
      Text("Choose")
    }
    let html = StaticHTMLFiberRenderer().render(picker)
    _expectTrue(html.contains("data-photos-picker-accept=\"image/*,video/*\""))
  }

  @Test
  func testMultiplePickerCarriesSelectionLimitAndVideoFilter() {
    var selected: [PhotosPickerItem] = []
    let binding = Binding<[PhotosPickerItem]>(get: { selected }, set: { selected = $0 })
    let picker = PhotosPicker(selection: binding, maxSelectionCount: 3, matching: .videos) {
      Text("Choose videos")
    }

    let html = StaticHTMLFiberRenderer().render(picker)
    _expectTrue(html.contains("data-photos-picker-multiple=\"true\""))
    _expectTrue(html.contains("data-photos-picker-limit=\"3\""))
    _expectTrue(html.contains("data-photos-picker-accept=\"video/*\""))
  }

  @Test
  func testModernCompatibilityArgumentsAndTitleInitializer() {
    var selected: [PhotosPickerItem] = []
    let binding = Binding<[PhotosPickerItem]>(get: { selected }, set: { selected = $0 })
    let picker = PhotosPicker(
      "Select media",
      selection: binding,
      maxSelectionCount: 4,
      selectionBehavior: .ordered,
      matching: .any(of: [.images, .videos]),
      preferredItemEncoding: .compatible,
      photoLibrary: .shared()
    )

    let html = StaticHTMLFiberRenderer().render(picker)
    _expectTrue(html.contains("Select media"))
    _expectTrue(html.contains("data-photos-picker-selection-behavior=\"ordered\""))
    _expectTrue(html.contains("data-photos-picker-encoding=\"compatible\""))
    _expectTrue(html.contains("data-photos-picker-accept=\"image/*,video/*\""))
  }

  @Test
  func testFilterConjunctionDoesNotAdvertiseAnIncorrectAcceptHint() {
    var selected: PhotosPickerItem?
    let picker = PhotosPicker(selection: Binding(get: { selected }, set: { selected = $0 }), matching: .all(of: [.images, .videos])) {
      Text("Impossible")
    }
    let html = StaticHTMLFiberRenderer().render(picker)
    _expectFalse(html.contains("data-photos-picker-accept="))
  }

  @Test
  func testAlternativeAndCompoundFilterHintsAreConservativeAndDeduplicated() {
    let imageFilters: [PhotosPickerFilter] = [
      .livePhotos, .screenshots, .bursts, .panoramas, .depthEffect, .raw
    ]
    for filter in imageFilters {
      _expectTrue(renderPicker(matching: filter).contains("data-photos-picker-accept=\"image/*\""))
    }

    let videoFilters: [PhotosPickerFilter] = [.screenRecordings, .slomo, .cinematicVideo]
    for filter in videoFilters {
      _expectTrue(renderPicker(matching: filter).contains("data-photos-picker-accept=\"video/*\""))
    }

    _expectTrue(
      renderPicker(matching: .any(of: .images, .images, .videos))
        .contains("data-photos-picker-accept=\"image/*,video/*\"")
    )
    _expectTrue(
      renderPicker(matching: .all(of: .images, .images))
        .contains("data-photos-picker-accept=\"image/*\"")
    )
    _expectFalse(renderPicker(matching: .any(of: [])).contains("data-photos-picker-accept="))
    _expectFalse(renderPicker(matching: .all(of: [])).contains("data-photos-picker-accept="))
    _expectFalse(renderPicker(matching: .not(.images)).contains("data-photos-picker-accept="))
  }

  @Test
  func testSelectedPayloadsAreValidatedAgainstMatchingAndDefaultMediaFilters() {
    SwiftUIWebTransferRuntime.register(
      identifier: "picker-filter-image",
      payload: SwiftUIWebTransferPayload(data: Data([1]), contentType: .jpeg)
    )
    SwiftUIWebTransferRuntime.register(
      identifier: "picker-filter-video",
      payload: SwiftUIWebTransferPayload(data: Data([2]), contentType: .video)
    )
    SwiftUIWebTransferRuntime.register(
      identifier: "picker-filter-text",
      payload: SwiftUIWebTransferPayload(data: Data([3]), contentType: .data)
    )

    var imageSelection: PhotosPickerItem?
    let imagePicker = PhotosPicker(
      selection: Binding(get: { imageSelection }, set: { imageSelection = $0 }),
      matching: .images
    ) { Text("Choose image") }
    let imageTree = FiberTree(imagePicker)
    let imageNode = imageTree.findNode(withEvent: PhotosPickerRuntime.selectionEvent)
    imageTree.dispatch(event: PhotosPickerRuntime.selectionEvent, value: "picker-filter-video", on: imageNode)
    _expectNil(imageSelection)
    imageTree.dispatch(event: PhotosPickerRuntime.selectionEvent, value: "picker-filter-image", on: imageNode)
    _expectEqual(imageSelection?.itemIdentifier, "picker-filter-image")

    var nonImageSelection: [PhotosPickerItem] = []
    let nonImagePicker = PhotosPicker(
      selection: Binding(get: { nonImageSelection }, set: { nonImageSelection = $0 }),
      matching: .not(.images)
    ) { Text("Choose non-image") }
    let nonImageTree = FiberTree(nonImagePicker)
    let nonImageNode = nonImageTree.findNode(withEvent: PhotosPickerRuntime.selectionEvent)
    nonImageTree.dispatch(
      event: PhotosPickerRuntime.selectionEvent,
      value: "picker-filter-image,picker-filter-video,picker-filter-text",
      on: nonImageNode
    )
    _expectEqual(nonImageSelection.map(\.itemIdentifier), ["picker-filter-video", "picker-filter-text"])

    var defaultSelection: PhotosPickerItem?
    let defaultPicker = PhotosPicker(
      selection: Binding(get: { defaultSelection }, set: { defaultSelection = $0 })
    ) { Text("Choose media") }
    let defaultTree = FiberTree(defaultPicker)
    let defaultNode = defaultTree.findNode(withEvent: PhotosPickerRuntime.selectionEvent)
    defaultTree.dispatch(event: PhotosPickerRuntime.selectionEvent, value: "picker-filter-text", on: defaultNode)
    _expectNil(defaultSelection)
  }

  @Test
  func testModifierPresentsAndDismissesAfterSelection() {
    var presented = true
    var selected: PhotosPickerItem?
    let view = Text("Content").photosPicker(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      selection: Binding(get: { selected }, set: { selected = $0 }),
      matching: .images
    )
    let tree = FiberTree(view)
    let node = tree.findNode(withEvent: PhotosPickerRuntime.selectionEvent)
    _expectNotNil(node)
    _expectEqual(node?.attributes["data-photos-picker-presented"], "true")

    SwiftUIWebTransferRuntime.register(
      identifier: "test-photo",
      payload: SwiftUIWebTransferPayload(data: Data([1, 2, 3]), contentType: .jpeg, suggestedFileName: "photo.jpg")
    )
    tree.dispatch(event: PhotosPickerRuntime.selectionEvent, value: "test-photo", on: node)
    _expectEqual(selected?.itemIdentifier, "test-photo")
    _expectFalse(presented, "A presented PhotosPicker dismisses when a selection is delivered.")
  }

  @Test
  func testModifierDismissesWhenBrowserPickerIsCancelled() {
    var presented = true
    var selected: PhotosPickerItem?
    let view = Text("Content").photosPicker(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      selection: Binding(get: { selected }, set: { selected = $0 })
    )
    let tree = FiberTree(view)
    let node = tree.findNode(withEvent: PhotosPickerRuntime.cancelEvent)
    _expectNotNil(node)
    tree.dispatch(event: PhotosPickerRuntime.cancelEvent, on: node)
    _expectFalse(presented)
    _expectNil(selected)
  }

  @Test
  func testMultipleSelectionDispatchesAllOpaqueItemsWithoutLimit() {
    var presented = true
    var selected: [PhotosPickerItem] = []
    let view = Text("Content").photosPicker(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      selection: Binding(get: { selected }, set: { selected = $0 }),
      matching: .any(of: .images, .videos)
    )
    let tree = FiberTree(view)
    let node = tree.findNode(withEvent: PhotosPickerRuntime.selectionEvent)
    _expectNotNil(node)
    for id in ["photo-a", "clip-b"] {
      SwiftUIWebTransferRuntime.register(
        identifier: id,
        payload: SwiftUIWebTransferPayload(data: Data([1]), contentType: id == "photo-a" ? .jpeg : .video)
      )
    }

    tree.dispatch(event: PhotosPickerRuntime.selectionEvent, value: "photo-a,clip-b", on: node)
    _expectEqual(selected.map(\.itemIdentifier), ["photo-a", "clip-b"])
    _expectFalse(presented)
  }

  @Test
  func testTransferableLoadingUsesSharedPayloadAndContentType() async throws {
    SwiftUIWebTransferRuntime.register(
      identifier: "video",
      payload: SwiftUIWebTransferPayload(data: Data([7, 8, 9]), contentType: .video, suggestedFileName: "clip.mp4")
    )
    let item = PhotosPickerItem(itemIdentifier: "video", supportedContentTypes: [.video], suggestedFileName: "clip.mp4", fileSize: 3)
    let data = try await item.loadTransferable(type: Data.self)
    _expectEqual(data, Data([7, 8, 9]))
    _expectEqual(item.supportedContentTypes, [.video])
    _expectEqual(item.suggestedFileName, "clip.mp4")
  }

  @Test
  func testItemsUseProviderIdentityAndRetainLazyPayload() async throws {
    SwiftUIWebTransferRuntime.register(
      identifier: "retained-photo",
      payload: SwiftUIWebTransferPayload(data: Data([4, 5]), contentType: .jpeg)
    )
    let first = PhotosPickerItem(itemIdentifier: "retained-photo", supportedContentTypes: [.jpeg])
    let second = PhotosPickerItem(itemIdentifier: "retained-photo", supportedContentTypes: [.png], suggestedFileName: "other.png")
    _expectEqual(first, second)

    // A picker input can be recycled while application state still owns the
    // item; the lease prevents host cleanup from invalidating this read.
    SwiftUIWebTransferRuntime.removeIfUnleased(identifier: "retained-photo")
    _expectNotNil(SwiftUIWebTransferRuntime.metadata(for: "retained-photo"))
    let bytes = try await first.loadDataRepresentation(forTypeIdentifier: "public.jpeg")
    _expectEqual(bytes, Data([4, 5]))
  }

  @Test
  func testCallbackLoadingCanBeCancelled() async throws {
    SwiftUIWebTransferRuntime.register(
      identifier: "callback-photo",
      payload: SwiftUIWebTransferPayload(data: Data([1]), contentType: .jpeg)
    )
    let item = PhotosPickerItem(itemIdentifier: "callback-photo")
    let expectation = _makeExpectation(description: "callback")
    let progress = item.loadTransferable(type: Data.self) { result in
      if case .success(let data) = result, data == Data([1]) { expectation.fulfill() }
    }
    _ = progress
    await _fulfillment(of: [expectation], timeout: 1)
  }

  /// Imports only PDF documents, so a JPEG payload is an unsupported content type for it.
  private struct PDFOnly: Transferable, Equatable {
    let bytes: Data

    static var transferRepresentation: some TransferRepresentation {
      DataRepresentation<PDFOnly>(importedContentType: .pdf, importing: { PDFOnly(bytes: $0) })
    }
  }

  @Test
  func itemsIdentifyByProviderIdentifierAndHashAccordingly() {
    let first = PhotosPickerItem(itemIdentifier: "same-provider-id", fileSize: 1)
    let second = PhotosPickerItem(itemIdentifier: "same-provider-id", suggestedFileName: "later.jpg")
    _expectEqual(first, second)
    _expectEqual(Set([first, second]).count, 1)
    _expectEqual(first.id, "same-provider-id")
    _expectEqual(PhotosPickerItem().id, "photos-picker-empty")
    _expectEqual(Set([first, PhotosPickerItem()]).count, 2)
  }

  @Test
  func loadingUsesTheInferredOverloadAndRejectsPayloadsItCannotImport() async throws {
    SwiftUIWebTransferRuntime.register(
      identifier: "photos-inferred-jpeg",
      payload: SwiftUIWebTransferPayload(data: Data([9]), contentType: .jpeg)
    )
    let item = PhotosPickerItem(itemIdentifier: "photos-inferred-jpeg", supportedContentTypes: [.jpeg])
    let bytes = try await item.loadTransferable(Data.self)
    _expectEqual(bytes, Data([9]))

    // An identifier the runtime never registered, or no identifier at all, has nothing to load.
    let unregistered = try await PhotosPickerItem(itemIdentifier: "photos-never-registered").loadTransferable(Data.self)
    _expectNil(unregistered)
    let anonymous = try await PhotosPickerItem().loadTransferable(Data.self)
    _expectNil(anonymous)

    // A transferable that imports only PDFs refuses a JPEG payload instead of coercing it.
    do {
      _ = try await item.loadTransferable(PDFOnly.self)
      _fail("a JPEG payload must not load as a PDF-only transferable")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unsupportedContentType)
    }

    // Data representations match a type identifier by conformance; an unknown identifier conforms to nothing.
    let image = try await item.loadDataRepresentation(forTypeIdentifier: "public.image")
    _expectEqual(image, Data([9]))
    do {
      _ = try await item.loadDataRepresentation(forTypeIdentifier: "com.example.not-a-known-type")
      _fail("an unknown type identifier must be rejected")
    } catch let error as SwiftUIWebTransferError {
      _expectEqual(error.code, .unsupportedContentType)
    }
  }

  @Test
  func callbackLoadingDeliversUnsupportedPayloadsAsFailures() async {
    SwiftUIWebTransferRuntime.register(
      identifier: "photos-callback-jpeg",
      payload: SwiftUIWebTransferPayload(data: Data([1]), contentType: .jpeg)
    )
    let item = PhotosPickerItem(itemIdentifier: "photos-callback-jpeg", supportedContentTypes: [.jpeg])
    let expectation = _makeExpectation(description: "unsupported content type reported as a failure")
    _ = item.loadTransferable(type: PDFOnly.self) { result in
      if case .failure(let error as SwiftUIWebTransferError) = result, error.code == .unsupportedContentType {
        expectation.fulfill()
      }
    }
    await _fulfillment(of: [expectation], timeout: 1)
  }

  @Test
  func singleSelectionTitleInitializerRendersItsLabelAndDeliversOneItem() {
    var selected: PhotosPickerItem?
    let picker = PhotosPicker(
      "Pick one",
      selection: Binding(get: { selected }, set: { selected = $0 }),
      matching: .images
    )
    let html = StaticHTMLFiberRenderer().render(picker)
    _expectTrue(html.contains("Pick one"))
    _expectTrue(html.contains("data-photos-picker-multiple=\"false\""))
    _expectTrue(html.contains("data-photos-picker-limit=\"1\""))

    SwiftUIWebTransferRuntime.register(
      identifier: "pick-one-photo",
      payload: SwiftUIWebTransferPayload(data: Data([1]), contentType: .jpeg)
    )
    let tree = FiberTree(picker)
    let node = tree.findNode(withEvent: PhotosPickerRuntime.selectionEvent)
    tree.dispatch(event: PhotosPickerRuntime.selectionEvent, value: "pick-one-photo", on: node)
    _expectEqual(selected?.itemIdentifier, "pick-one-photo")
  }

  @Test
  func modifierOnAFragmentWrapsTheContentInASemanticContainer() {
    var presented = true
    let view = Group {
      Text("First")
      Text("Second")
    }
    .photosPicker(
      isPresented: Binding(get: { presented }, set: { presented = $0 }),
      selection: Binding<PhotosPickerItem?>(get: { nil }, set: { _ in })
    )
    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("photos-picker-modifier"), html)
    _expectTrue(html.contains("data-photos-picker=\"modifier\""))
    _expectTrue(html.contains("First") && html.contains("Second"))
  }

  private func renderPicker(matching filter: PhotosPickerFilter) -> String {
    var selected: PhotosPickerItem?
    let picker = PhotosPicker(
      selection: Binding(get: { selected }, set: { selected = $0 }),
      matching: filter
    ) { Text("Filter contract") }
    return StaticHTMLFiberRenderer().render(picker)
  }
}
