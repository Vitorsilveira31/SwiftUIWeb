// SwiftUI-shaped drag and drop APIs.  The values in this file deliberately
// stop at transfer metadata and byte payloads; browser DataTransfer/File
// objects are owned by SwiftUIWebBrowser.

@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

package func _swiftUIWebContentTypeMatches(_ value: UTType, requested: UTType) -> Bool {
  value == requested || value.conforms(to: requested) ||
    (value.preferredMIMEType != nil && value.preferredMIMEType == requested.preferredMIMEType)
}

/// Foundation-free URL values are part of SwiftUIWeb's compatibility surface;
/// making them Transferable here keeps URL drags/drop destinations source
/// compatible on both native and Embedded hosts.
extension URL: Transferable {
  public typealias Representation = DataRepresentation<URL>
  public static var transferRepresentation: DataRepresentation<URL> {
    DataRepresentation(contentType: .url, exporting: { value in Data(value.absoluteString.utf8) }, importing: { data in
      guard let value = URL(string: String(decoding: data, as: UTF8.self)) else {
        throw SwiftUIWebTransferError(.invalidData, message: "The transferred value is not a URL")
      }
      return value
    })
  }
}

/// `loadTransferable(type: Image.self)` on a picked photo: the picked bytes become an image. The importer receives
/// only the bytes, so the image's type is read from them. The bytes travel in a `data:` URL, which the page already
/// holds; an image is not exported.
extension Image: Transferable {
  public typealias Representation = DataRepresentation<Image>
  public static var transferRepresentation: DataRepresentation<Image> {
    DataRepresentation(importedContentType: .image, importing: { data in
      Image(_dataURL: "data:\(_imageMIMEType(of: data));base64,\(data.base64EncodedString())")
    })
  }

  /// An image whose source is a `data:` URL, as a picked file's bytes are shown.
  package init(_dataURL source: String) { self.init(source, alt: nil) }
}

/// The MIME type of an image from its leading bytes (PNG, JPEG, GIF, WebP); other bytes are `application/octet-stream`.
private func _imageMIMEType(of data: Data) -> String {
  let head = Array(data.prefix(12))
  func starts(_ signature: [UInt8]) -> Bool { head.count >= signature.count && Array(head[0..<signature.count]) == signature }
  if starts([0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
  if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
  if starts([0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
  if head.count >= 12 && Array(head[0..<4]) == [0x52, 0x49, 0x46, 0x46] && Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] { return "image/webp" }
  return "application/octet-stream"
}

/// The data representations registered on a provider after it was made, shared by the copies of the provider as
/// Foundation's `NSItemProvider` is a class. Two sets are equal when they are the same one, or both empty: providers the
/// browser delivered for the same item stay equal.
package final class _ItemProviderRegistrations: Hashable, @unchecked Sendable {
  private let lock = _RuntimeLock()
  private var entries: [(identifier: String, load: @Sendable () -> Data?)] = []

  package init() {}

  func append(identifier: String, load: @escaping @Sendable () -> Data?) {
    lock.withLock { entries.append((identifier, load)) }
  }

  var identifiers: [String] { lock.withLock { entries.map { $0.identifier } } }

  /// The registered representations, each loaded now; one whose loader gives no data is left out.
  func payloads() -> [SwiftUIWebTransferPayload] {
    let current = lock.withLock { entries }
    return current.compactMap { entry in
      entry.load().map { SwiftUIWebTransferPayload(data: $0, contentType: UTType(entry.identifier)) }
    }
  }

  private var isEmpty: Bool { lock.withLock { entries.isEmpty } }

  package static func == (lhs: _ItemProviderRegistrations, rhs: _ItemProviderRegistrations) -> Bool {
    lhs === rhs || (lhs.isEmpty && rhs.isEmpty)
  }

  package func hash(into hasher: inout Hasher) {
    if isEmpty { hasher.combine(0) } else { hasher.combine(ObjectIdentifier(self)) }
  }
}

/// An item a drag source supplies or a drop or paste delivers, named as SwiftUI names it.
///
/// Drag sources build one with the empty initializer and the package constructors
/// backing ``View/onDrag(_:)``. Drops and pastes receive providers whose bytes
/// load lazily through the transfer runtime, so a browser File/Blob is read only
/// when the application asks for it.
public struct NSItemProvider: Hashable, Sendable {
  /// The payloads a drag source exports when a drag starts: the ones it was made with, then the data
  /// representations registered on it that load when asked.
  package var payloads: [SwiftUIWebTransferPayload] { basePayloads + registrations.payloads() }
  /// The UTI and MIME identifiers the item advertises, as Foundation's `registeredTypeIdentifiers` does.
  public var registeredTypeIdentifiers: [String] { baseIdentifiers + registrations.identifiers }
  /// The file name the item suggests, if any.
  public let suggestedName: String?

  private let identifier: String
  private let contentType: UTType
  private let lease: SwiftUIWebTransferLease?
  private let immediatePayload: SwiftUIWebTransferPayload?
  private let basePayloads: [SwiftUIWebTransferPayload]
  private let baseIdentifiers: [String]
  /// The representations registered on the provider after it was made (`registerDataRepresentation`); a provider is
  /// shared, as Foundation's class is, so a copy sees them too.
  private let registrations = _ItemProviderRegistrations()

  /// An empty provider, as SwiftUI's `NSItemProvider()` is.
  public init() { self.init(payloads: []) }

  /// A drag source's provider: its payloads are published when the drag starts.
  package init(payloads: [SwiftUIWebTransferPayload]) {
    basePayloads = payloads
    identifier = "item-provider-\(SwiftUIWebItemProviderCounter.next())"
    contentType = payloads.first?.contentType ?? .data
    baseIdentifiers = payloads.map { $0.contentType.identifier }
    suggestedName = payloads.first?.suggestedFileName
    lease = nil
    immediatePayload = payloads.first
  }

  /// Creates a provider backed by an in-memory payload. The payload is registered with the
  /// transfer runtime, so ``loadTransferable(type:)`` and the browser can read it later.
  package init(payload: SwiftUIWebTransferPayload) {
    let identifier = "item-provider-\(SwiftUIWebItemProviderCounter.next())"
    contentType = payload.contentType
    suggestedName = payload.suggestedFileName
    baseIdentifiers = [payload.contentType.identifier]
    self.identifier = identifier
    immediatePayload = payload
    basePayloads = [payload]
    SwiftUIWebTransferRuntime.register(identifier: identifier, payload: payload)
    // Capture the generation created by `register`. Taking the lease first
    // would record `nil`, so its deinitializer could never release the newly
    // registered payload.
    lease = SwiftUIWebTransferLease(identifier: identifier)
  }

  /// A browser-delivered provider: the bytes stay in the browser until loaded.
  @_spi(Renderer) public init(identifier: String, metadata: SwiftUIWebTransferMetadata, lease: SwiftUIWebTransferLease? = nil) {
    self.identifier = identifier
    contentType = metadata.contentType ?? .data
    suggestedName = metadata.suggestedFileName
    baseIdentifiers = metadata.contentTypes.map { $0.identifier }
    self.lease = lease
    immediatePayload = nil
    basePayloads = []
  }

  /// In-memory plain text for drops that must validate synchronously before
  /// the browser event returns, such as small executor identifiers.
  @_spi(Renderer) public var plainTextValue: String? {
    guard let immediatePayload,
          immediatePayload.contentType.preferredMIMEType?.lowercased() == "text/plain" else { return nil }
    return String(decoding: immediatePayload.data, as: UTF8.self)
  }

  /// The UTI of the item's primary representation.
  @_spi(Renderer) public var primaryContentType: UTType { contentType }

  /// Loads the item bytes.  The browser adapter can keep a native File/Blob
  /// lazy and only materialize it at this call site.
  @_spi(Renderer) public func loadData() async throws -> Data {
    guard let payload = try await SwiftUIWebTransferRuntime.load(identifier: identifier) else {
      throw SwiftUIWebTransferError(.unavailable, message: "The drop item is no longer available")
    }
    return payload.data
  }

  /// Loads the item as `type`, using the first representation it can import.
  @_spi(Renderer) public func loadTransferable<T: Transferable>(type: T.Type = T.self) async throws -> T? {
    try await SwiftUIWebTransferRuntime.load(identifier: identifier, as: type)
  }

  @_spi(Renderer) public var _identifier: String { identifier }

  /// Whether the item has a representation of `typeIdentifier` or of a type that conforms to it, as Foundation's
  /// `hasItemConformingToTypeIdentifier(_:)` answers.
  public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
    let wanted = UTType(typeIdentifier)
    return registeredTypeIdentifiers.contains { $0 == typeIdentifier || UTType($0).conforms(to: wanted) }
  }

  /// Registers a data representation that `load` supplies when it is asked for (Foundation's
  /// `registerDataRepresentation` is in WebFoundation, which owns `Progress`).
  package func _registerDataRepresentation(forTypeIdentifier typeIdentifier: String, load: @escaping @Sendable () -> Data?) {
    registrations.append(identifier: typeIdentifier, load: load)
  }

  /// Convenience constructors for the framework's own drag sources and tests.
  package static func text(_ value: String) -> NSItemProvider {
    NSItemProvider(payload: SwiftUIWebTransferPayload(data: Data(value.utf8), contentType: .utf8PlainText))
  }

  package static func url(_ value: String) -> NSItemProvider {
    NSItemProvider(payload: SwiftUIWebTransferPayload(data: Data(value.utf8), contentType: .url))
  }

  package static func file(_ data: Data, contentType: UTType = .data, suggestedFileName: String? = nil) -> NSItemProvider {
    NSItemProvider(payload: SwiftUIWebTransferPayload(data: data, contentType: contentType, suggestedFileName: suggestedFileName))
  }
}

private enum SwiftUIWebItemProviderCounter {
  private static let value = _Locked<UInt64>(0)
  static func next() -> UInt64 { value.withLock { $0 &+= 1; return $0 } }
}

/// The location and advertised types of a browser drop, expressed without a
/// DOM event.  ``types`` contains UTI identifiers (and MIME identifiers when
/// no known UTI exists).
public struct DropInfo: Sendable {
  public let location: CGPoint
  @_spi(Renderer) public let types: [UTType]
  // SAFETY: providers are created and read on the main actor (drop events); Foundation's NSItemProvider is not
  // Sendable, and the native drop value only carries it between those two points.
  private let providers: [NSItemProvider]

  @_spi(Renderer) public init(location: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint, types: [UTType] = []) {
    self.location = location
    self.types = types
    providers = []
  }

  @_spi(Renderer) public init(location: CGPoint, types: [UTType], providers: [NSItemProvider]) {
    self.location = location
    self.types = types
    self.providers = providers
  }

  @_spi(Renderer) public var hasItems: Bool { !types.isEmpty }

  public func hasItemsConforming(to contentTypes: [UTType]) -> Bool {
    types.contains { type in contentTypes.contains { _swiftUIWebContentTypeMatches(type, requested: $0) } }
  }

  /// Returns the providers whose advertised content type conforms to one of
  /// the requested types.  The browser-backed providers remain lazy.
  public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] {
    guard !contentTypes.isEmpty else { return providers }
    return providers.filter { provider in
      contentTypes.contains { requested in _swiftUIWebContentTypeMatches(provider.primaryContentType, requested: requested) }
    }
  }
}

/// Renderer descriptor installed by ``View/onDrag(_:)`` and ``View/draggable(_:)``.  Browser hosts export the
/// value only when a drag starts, keeping ordinary renders allocation-free.
@_spi(Renderer) public struct _DragSourceDescriptor {
  public let export: @MainActor () async throws -> [SwiftUIWebTransferPayload]
  /// Synchronous fast path used by legacy providers.  HTML only permits
  /// `DataTransfer.setData` during the `dragstart` dispatch, so in-memory
  /// payloads are published before the event returns.
  public let synchronousExport: (@MainActor () -> [SwiftUIWebTransferPayload])?
  public let preferredTypes: [UTType]
  public let embeddedText: String?
  public let onStarted: (@MainActor () -> Void)?

  public init(export: @escaping @MainActor () async throws -> [SwiftUIWebTransferPayload], synchronousExport: (@MainActor () -> [SwiftUIWebTransferPayload])? = nil, preferredTypes: [UTType] = [], embeddedText: String? = nil, onStarted: (@MainActor () -> Void)? = nil) {
    self.export = export
    self.synchronousExport = synchronousExport
    self.preferredTypes = preferredTypes
    self.embeddedText = embeddedText
    self.onStarted = onStarted
  }
}

/// Renderer descriptor installed by the drop-target modifiers.
@_spi(Renderer) public struct _DropTargetDescriptor {
  public let acceptedTypes: [UTType]
  public let targeted: (@MainActor (Bool) -> Void)?
  public let perform: @MainActor ([NSItemProvider], DropInfo) -> Bool

  public init(acceptedTypes: [UTType], targeted: (@MainActor (Bool) -> Void)? = nil, perform: @escaping @MainActor ([NSItemProvider], DropInfo) -> Bool) {
    self.acceptedTypes = acceptedTypes
    self.targeted = targeted
    self.perform = perform
  }
}

package nonisolated struct DragSourceModifier: ViewModifier {
  let descriptor: _DragSourceDescriptor
  package init(descriptor: _DragSourceDescriptor) { self.descriptor = descriptor }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    guard context.environment.isEnabled else { return }
    node.attributes["draggable"] = "true"
    node.attributes["data-drag-source"] = "true"
    #if hasFeature(Embedded)
    if let text = descriptor.embeddedText { node.attributes["data-embedded-drag-text"] = text }
    if let onStarted = descriptor.onStarted {
      node.events["embeddedDragStarted"] = _EventHandler(name: "embeddedDragStarted", action: { _ in onStarted() })
    }
    #endif
    node._dragSource = descriptor
  }
}

public extension View {

  /// Drags a Transferable value. Exporting is deferred until the drag starts, and the browser
  /// advertises every representation the value has.
  nonisolated func draggable<T: Transferable>(_ payload: @autoclosure @escaping () -> T) -> some View {
    nonisolated(unsafe) let payload = payload
    return _modified(DragSourceModifier(descriptor: _DragSourceDescriptor(
      export: { try await payload()._swiftUIWebExportAll() },
      preferredTypes: T.exportedContentTypes(),
      embeddedText: _swiftUIWebDescribe(payload())
    )))
  }

  /// Preview-bearing spelling. Browser hosts use the native drag preview generated by the user agent; the
  /// SwiftUI preview closure remains intentionally side-effect free and is not mounted as a second subtree.
  nonisolated func draggable<T: Transferable, V: View>(_ payload: @autoclosure @escaping () -> T, @ViewBuilder preview: @escaping () -> V) -> some View {
    _ = preview
    return draggable(payload())
  }

}

// MARK: Delegate-based drop

public enum DropOperation: Sendable { case cancel, forbidden, copy, move }
public struct DropProposal: Sendable {
  public var operation: DropOperation
  public init(operation: DropOperation) { self.operation = operation }
}

@MainActor @preconcurrency public protocol DropDelegate {
  @MainActor @preconcurrency func validateDrop(info: DropInfo) -> Bool
  @MainActor @preconcurrency func dropEntered(info: DropInfo)
  @MainActor @preconcurrency func dropUpdated(info: DropInfo) -> DropProposal?
  @MainActor @preconcurrency func dropExited(info: DropInfo)
  @MainActor @preconcurrency func performDrop(info: DropInfo) -> Bool
}

public extension DropDelegate {
  func validateDrop(info: DropInfo) -> Bool { true }
  func dropEntered(info: DropInfo) {}
  func dropUpdated(info: DropInfo) -> DropProposal? { nil }
  func dropExited(info: DropInfo) {}
}

