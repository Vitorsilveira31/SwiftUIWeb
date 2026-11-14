
/// Whether `type` conforms to the type named `identifier`. Apple's `UTType(_:)` is failable (an unknown identifier
/// is `nil`); the Embedded stand-in is not. An unknown identifier conforms to nothing.
private func _conforms(_ type: UTType, toIdentifier identifier: String) -> Bool {
  return type.conforms(to: UTType(identifier))
}
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebTransferable
@_exported import SwiftUIWebTransferable


/// A browser-neutral stand-in for PhotosUI's photo-library handle.
///
/// Browsers do not expose the user's Photos library as a process-wide object;
/// the host therefore uses the default local-file provider for every value.
/// Keeping this value in the Swift-facing module means code that passes
/// `photoLibrary: .shared()` remains source-compatible without leaking a
/// platform Photos framework into WebAssembly builds.
public struct PHPhotoLibrary: Hashable, Sendable {
  public init() {}
  public static func shared() -> PHPhotoLibrary { PHPhotoLibrary() }
}

/// Controls the order in which a multiple-selection picker reports items.
/// The browser input already reports files in the order selected by the user;
/// the value is retained as semantic metadata so a future native host can
/// implement continuous selection policies as well.
public struct PhotosPickerSelectionBehavior: Hashable, Sendable {
  fileprivate enum Value: String, Hashable, Sendable { case `default`, ordered, continuous, continuousAndOrdered }
  fileprivate let value: Value

  private init(_ value: Value) { self.value = value }
  public static let `default` = PhotosPickerSelectionBehavior(.default)
  public static let ordered = PhotosPickerSelectionBehavior(.ordered)
  public static let continuous = PhotosPickerSelectionBehavior(.continuous)
  public static let continuousAndOrdered = PhotosPickerSelectionBehavior(.continuousAndOrdered)
}

/// A SwiftUI-compatible media filter.  The browser host maps image/video
/// filters to an `accept` hint; the selected item's actual MIME type remains
/// authoritative and is exposed through the shared content-type layer.
public indirect enum PhotosPickerFilter: Hashable, Sendable {
  case images
  case videos
  case livePhotos
  case screenshots
  case screenRecordings
  case bursts
  case panoramas
  case slomo
  case depthEffect
  case cinematicVideo
  case raw
  case any(of: [PhotosPickerFilter])
  case all(of: [PhotosPickerFilter])
  case not(PhotosPickerFilter)

  public static let image = PhotosPickerFilter.images
  public static let video = PhotosPickerFilter.videos

  public static func any(of filters: PhotosPickerFilter...) -> PhotosPickerFilter { .any(of: filters) }
  public static func all(of filters: PhotosPickerFilter...) -> PhotosPickerFilter { .all(of: filters) }

  /// MIME values suitable for an HTML `accept` hint.  This is intentionally
  /// internal to the renderer; application code only handles this Swift value.
  var acceptedMIMETypes: [String] {
    switch self {
    case .images: return ["image/*"]
    case .videos: return ["video/*"]
    case .livePhotos, .screenshots, .bursts, .panoramas, .depthEffect, .raw:
      return ["image/*"]
    case .screenRecordings, .slomo, .cinematicVideo:
      return ["video/*"]
    case .any(let filters):
      return filters.flatMap { filter in filter.acceptedMIMETypes }.deduplicated()
    case .all(let filters):
      // `accept` is only a hint and cannot express arbitrary conjunctions.
      // Keep a MIME family only when every child agrees on that family;
      // otherwise leave the hint empty and let the host perform best-effort
      // post-filtering.
      let values = filters.map { filter in filter.acceptedMIMETypes }
      guard let first = values.first, !first.isEmpty,
            values.dropFirst().allSatisfy({ $0 == first }) else { return [] }
      return first
    case .not:
      // HTML cannot express a negated accept filter. An omitted hint retains
      // the browser's full picker and the host performs best-effort filtering.
      return []
    }
  }

  func accepts(_ type: UTType) -> Bool {
    switch self {
    case .images: return type.isImage
    case .videos: return type.isVideo
    case .livePhotos, .screenshots, .bursts, .panoramas, .depthEffect, .raw: return type.isImage
    case .screenRecordings, .slomo, .cinematicVideo: return type.isVideo
    case .any(let filters): return filters.contains { $0.accepts(type) }
    case .all(let filters): return filters.allSatisfy { $0.accepts(type) }
    case .not(let filter): return !filter.accepts(type)
    }
  }
}

/// Source-compatible spelling used by SwiftUI's PhotosPicker API.
public typealias PHPickerFilter = PhotosPickerFilter

public struct PhotosPickerItem: Hashable, Identifiable, Sendable {
  /// SwiftUI calls this policy `EncodingDisambiguationPolicy`. The shorter
  /// `EncodingAvailability` alias is kept for source compatibility with an
  /// earlier SwiftUIWeb preview.
  public enum EncodingDisambiguationPolicy: String, Hashable, Sendable {
    case automatic
    case current
    case compatible
  }

  public typealias EncodingAvailability = EncodingDisambiguationPolicy

  private final class Storage: @unchecked Sendable {
    let lease: SwiftUIWebTransferLease?
    init(identifier: String?) {
      lease = identifier.map { SwiftUIWebTransferLease(identifier: $0) }
    }
  }

  public let itemIdentifier: String?
  public let supportedContentTypes: [UTType]
  public let suggestedFileName: String?
  public let fileSize: Int64?
  private let storage: Storage?
  public var id: String { itemIdentifier ?? "photos-picker-empty" }

  public init(
    itemIdentifier: String? = nil,
    supportedContentTypes: [UTType] = [.data],
    suggestedFileName: String? = nil,
    fileSize: Int64? = nil
  ) {
    self.itemIdentifier = itemIdentifier
    self.supportedContentTypes = supportedContentTypes
    self.suggestedFileName = suggestedFileName
    self.fileSize = fileSize
    storage = Storage(identifier: itemIdentifier)
  }

  public static func == (lhs: PhotosPickerItem, rhs: PhotosPickerItem) -> Bool {
    // PhotosUI identity is the provider's local identifier. Metadata can be
    // filled in lazily and must not make the same item compare unequal.
    lhs.itemIdentifier == rhs.itemIdentifier
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(itemIdentifier)
  }

  /// Loads the item through the shared Transferable runtime. Browser hosts
  /// read the underlying file asynchronously; native/WASI hosts can register
  /// in-memory payloads for previews and tests.
  public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
    guard let identifier = itemIdentifier else { return nil }
    guard let payload = try await SwiftUIWebTransferRuntime.load(identifier: identifier) else {
      return nil
    }
    let supported = T.importedContentTypes()
    // A generic `.data` payload goes only to a type whose importer accepts `.data`, as in Transferable's import filter.
    let accepted: Bool
    if payload.contentType == .data {
      accepted = supported.contains { $0.conforms(to: .data) }
    } else {
      accepted = supported.isEmpty || supported.contains(where: { $0 == .data || payload.contentType.conforms(to: $0) || $0.conforms(to: payload.contentType) })
    }
    guard accepted else {
      throw SwiftUIWebTransferError(.unsupportedContentType, message: "\(payload.contentType.mimeType) is not supported by \(T.self)")
    }
    // Let representation-based transferables (DataRepresentation,
    // CodableRepresentation, FileRepresentation, ProxyRepresentation, …)
    // choose their importer rather than forcing a PhotosUI-specific decoder.
    return try await T.importing(data: payload.data, contentType: payload.contentType)
  }

  /// Convenience spelling matching SwiftUI call sites that use an inferred
  /// transferable type.
  public func loadTransferable<T: Transferable>(_ type: T.Type) async throws -> T? {
    try await loadTransferable(type: type)
  }

  /// Loads raw bytes for callers that do not need to define a custom
  /// `Transferable`. This mirrors the useful PhotosUI item-provider operation
  /// while retaining the package's backend-neutral data value.
  public func loadDataRepresentation(forTypeIdentifier typeIdentifier: String) async throws -> Data? {
    guard let identifier = itemIdentifier,
          let payload = try await SwiftUIWebTransferRuntime.load(identifier: identifier) else { return nil }
    guard typeIdentifier.isEmpty || payload.contentType.identifier == typeIdentifier || _conforms(payload.contentType, toIdentifier: typeIdentifier) else {
      throw SwiftUIWebTransferError(.unsupportedContentType, message: "\(payload.contentType.identifier) is not \(typeIdentifier)")
    }
    return payload.data
  }

  /// Callback-based loading retained for source compatibility with older
  /// PhotosUI call sites. The returned progress object only owns cancellation;
  /// progress fractions are intentionally unavailable because browser file
  /// reads expose an atomic `arrayBuffer()` operation.
  @discardableResult
  public func loadTransferable<T: Transferable>(
    type: T.Type,
    completionHandler: @escaping @Sendable (Result<T?, Error>) -> Void
  ) -> PhotosPickerTransferProgress {
    let typeBox = _PhotosPickerTypeBox(type)
    let task = Task {
      do {
        completionHandler(.success(try await loadTransferable(type: typeBox.value)))
      } catch {
        completionHandler(.failure(error))
      }
    }
    return PhotosPickerTransferProgress(task: task)
  }

  /// Browser SPI: metadata is registered before the selection event reaches
  /// the application binding. No browser object crosses this boundary.
  @_spi(Browser) public static func _fromRegisteredIdentifier(_ identifier: String) -> PhotosPickerItem {
    let metadata = SwiftUIWebTransferRuntime.metadata(for: identifier)
    return PhotosPickerItem(
      itemIdentifier: identifier,
      supportedContentTypes: metadata?.contentTypes ?? [.data],
      suggestedFileName: metadata?.suggestedFileName,
      fileSize: metadata?.size
    )
  }
}

private func _resolvedPhotosPickerItem(
  identifier: String,
  matching filter: PhotosPickerFilter?
) -> PhotosPickerItem? {
  let item = PhotosPickerItem._fromRegisteredIdentifier(identifier)
  let effectiveFilter = filter ?? .any(of: .images, .videos)
  guard item.supportedContentTypes.contains(where: { effectiveFilter.accepts($0) }) else {
    return nil
  }
  return item
}

private func _resolvedPhotosPickerItems(
  encodedIdentifiers: String,
  matching filter: PhotosPickerFilter?,
  limit: Int?
) -> [PhotosPickerItem] {
  let items = encodedIdentifiers
    .split(separator: ",", omittingEmptySubsequences: true)
    .compactMap { _resolvedPhotosPickerItem(identifier: String($0), matching: filter) }
  // The host may return more than the selection limit; the app receives only the first items up to it (nil or 0: no limit).
  guard let limit, limit > 0 else { return items }
  return Array(items.prefix(limit))
}

private final class _PhotosPickerTypeBox<T> {
  let value: T.Type
  init(_ value: T.Type) { self.value = value }
}

/// Cancellation handle returned by callback-style PhotosPicker loads. Native
/// clients receive Foundation's familiar `Progress`; WASM keeps a tiny
/// equivalent that exposes the same `cancel()` operation.
public final class PhotosPickerTransferProgress: @unchecked Sendable {
  private let task: Task<Void, Never>
  fileprivate init(task: Task<Void, Never>) { self.task = task }
  public func cancel() { task.cancel() }
}

/// A labelled picker control. The rendered node is a semantic button; the
/// browser adapter creates its file input only when the user activates it.
public struct PhotosPicker<Label: View>: View {
  public typealias Body = Never

  private let label: () -> Label
  private let matching: PhotosPickerFilter?
  private let preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy
  private let selectionBehavior: PhotosPickerSelectionBehavior
  private let maxSelectionCount: Int?
  private let multiple: Bool
  private let onSelection: @MainActor (String) -> Void

  public init(
    selection: Binding<PhotosPickerItem?>,
    matching: PhotosPickerFilter? = nil,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
    photoLibrary: PHPhotoLibrary = .shared(),
    @ViewBuilder label: @escaping () -> Label
  ) {
    _ = photoLibrary
    self.label = label
    self.matching = matching
    self.preferredItemEncoding = preferredItemEncoding
    selectionBehavior = .default
    maxSelectionCount = 1
    multiple = false
    onSelection = { encoded in
      let identifier = encoded.split(separator: ",", omittingEmptySubsequences: true).first.map(String.init)
      let item = identifier.flatMap { _resolvedPhotosPickerItem(identifier: $0, matching: matching) }
      selection.wrappedValue = item
    }
  }

  public init(
    selection: Binding<[PhotosPickerItem]>,
    maxSelectionCount: Int? = nil,
    selectionBehavior: PhotosPickerSelectionBehavior = .default,
    matching: PhotosPickerFilter? = nil,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
    photoLibrary: PHPhotoLibrary = .shared(),
    @ViewBuilder label: @escaping () -> Label
  ) {
    _ = photoLibrary
    self.label = label
    self.matching = matching
    self.preferredItemEncoding = preferredItemEncoding
    self.selectionBehavior = selectionBehavior
    self.maxSelectionCount = maxSelectionCount.flatMap { $0 > 0 ? $0 : nil }
    multiple = true
    onSelection = { encoded in
      selection.wrappedValue = _resolvedPhotosPickerItems(encodedIdentifiers: encoded, matching: matching, limit: maxSelectionCount)
    }
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("button")
    node.classes = ["photos-picker"]
    node.attributes["type"] = "button"
    node.attributes["data-photos-picker"] = "button"
    node.attributes["data-photos-picker-multiple"] = multiple ? "true" : "false"
    node.attributes["data-photos-picker-encoding"] = preferredItemEncoding.rawValue
    node.attributes["data-photos-picker-selection-behavior"] = selectionBehavior.value.rawValue
    if let maxSelectionCount { node.attributes["data-photos-picker-limit"] = String(maxSelectionCount) }
    // PhotosPicker's default provider is media-only. A nil matching filter
    // therefore advertises images and videos, while explicit negated or
    // metadata-only filters intentionally omit the browser hint.
    let accept = matching?.acceptedMIMETypes ?? ["image/*", "video/*"]
    if !accept.isEmpty { node.attributes["data-photos-picker-accept"] = accept.joined(separator: ",") }
    node.events[PhotosPickerRuntime.selectionEvent] = _EventHandler(name: PhotosPickerRuntime.selectionEvent, action: onSelection)
    node.children = [label()._render(in: context)].filter { !$0.isEmpty }
    return node
  }
}

public extension PhotosPicker where Label == Text {
  /// Convenience title initialiser matching SwiftUI's `Text`-label overload.
  init(
    _ title: String,
    selection: Binding<PhotosPickerItem?>,
    matching: PhotosPickerFilter? = nil,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
    photoLibrary: PHPhotoLibrary = .shared()
  ) {
    self.init(selection: selection, matching: matching, preferredItemEncoding: preferredItemEncoding, photoLibrary: photoLibrary) {
      Text(title)
    }
  }

  /// Convenience title initialiser for multiple selection.
  init(
    _ title: String,
    selection: Binding<[PhotosPickerItem]>,
    maxSelectionCount: Int? = nil,
    selectionBehavior: PhotosPickerSelectionBehavior = .default,
    matching: PhotosPickerFilter? = nil,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
    photoLibrary: PHPhotoLibrary = .shared()
  ) {
    self.init(selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: matching, preferredItemEncoding: preferredItemEncoding, photoLibrary: photoLibrary) {
      Text(title)
    }
  }
}

/// Modifier implementation shared by single- and multiple-selection APIs.
public nonisolated struct PhotosPickerModifier: ViewModifier {
  private let isPresented: Binding<Bool>
  private let matching: PhotosPickerFilter?
  private let preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy
  private let selectionBehavior: PhotosPickerSelectionBehavior
  private let maxSelectionCount: Int?
  private let multiple: Bool
  private let onSelection: @MainActor (String) -> Void
  private let onCancel: @MainActor () -> Void

  init(
    isPresented: Binding<Bool>,
    selection: Binding<PhotosPickerItem?>,
    matching: PhotosPickerFilter?,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy,
    photoLibrary: PHPhotoLibrary = .shared()
  ) {
    _ = photoLibrary
    self.isPresented = isPresented
    self.matching = matching
    self.preferredItemEncoding = preferredItemEncoding
    selectionBehavior = .default
    maxSelectionCount = 1
    multiple = false
    onSelection = { encoded in
      let identifier = encoded.split(separator: ",", omittingEmptySubsequences: true).first.map(String.init)
      let item = identifier.flatMap { _resolvedPhotosPickerItem(identifier: $0, matching: matching) }
      selection.wrappedValue = item
      isPresented.wrappedValue = false
    }
    onCancel = { isPresented.wrappedValue = false }
  }

  init(
    isPresented: Binding<Bool>,
    selection: Binding<[PhotosPickerItem]>,
    maxSelectionCount: Int?,
    selectionBehavior: PhotosPickerSelectionBehavior = .default,
    matching: PhotosPickerFilter?,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy,
    photoLibrary: PHPhotoLibrary = .shared()
  ) {
    _ = photoLibrary
    self.isPresented = isPresented
    self.matching = matching
    self.preferredItemEncoding = preferredItemEncoding
    self.selectionBehavior = selectionBehavior
    self.maxSelectionCount = maxSelectionCount.flatMap { $0 > 0 ? $0 : nil }
    multiple = true
    onSelection = { encoded in
      selection.wrappedValue = _resolvedPhotosPickerItems(encodedIdentifiers: encoded, matching: matching, limit: maxSelectionCount)
      isPresented.wrappedValue = false
    }
    onCancel = { isPresented.wrappedValue = false }
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // A fragment/text root cannot carry host attributes. Preserve the user's
    // content and introduce one semantic wrapper in that uncommon case.
    if case .fragment = node.kind {
      let original = node.clone()
      node.kind = .element("div"); node.text = nil; node.children = [original]
    } else if case .text = node.kind {
      let original = node.clone()
      node.kind = .element("div"); node.text = nil; node.children = [original]
    }
    node.classes.append("photos-picker-modifier")
    node.attributes["data-photos-picker"] = "modifier"
    node.attributes["data-photos-picker-presented"] = isPresented.wrappedValue ? "true" : "false"
    node.attributes["data-photos-picker-multiple"] = multiple ? "true" : "false"
    node.attributes["data-photos-picker-encoding"] = preferredItemEncoding.rawValue
    node.attributes["data-photos-picker-selection-behavior"] = selectionBehavior.value.rawValue
    if let maxSelectionCount { node.attributes["data-photos-picker-limit"] = String(maxSelectionCount) }
    let accept = matching?.acceptedMIMETypes ?? ["image/*", "video/*"]
    if !accept.isEmpty { node.attributes["data-photos-picker-accept"] = accept.joined(separator: ",") }
    node.events[PhotosPickerRuntime.selectionEvent] = _EventHandler(name: PhotosPickerRuntime.selectionEvent, action: onSelection)
    node.events[PhotosPickerRuntime.cancelEvent] = _EventHandler(name: PhotosPickerRuntime.cancelEvent, action: onCancel)
  }
}

public extension View {
  nonisolated func photosPicker(
    isPresented: Binding<Bool>,
    selection: Binding<PhotosPickerItem?>,
    matching: PhotosPickerFilter? = nil,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
    photoLibrary: PHPhotoLibrary = .shared()
  ) -> ModifiedContent<Self, PhotosPickerModifier> {
    modifier(PhotosPickerModifier(isPresented: isPresented, selection: selection, matching: matching, preferredItemEncoding: preferredItemEncoding, photoLibrary: photoLibrary))
  }

  nonisolated func photosPicker(
    isPresented: Binding<Bool>,
    selection: Binding<[PhotosPickerItem]>,
    maxSelectionCount: Int? = nil,
    selectionBehavior: PhotosPickerSelectionBehavior = .default,
    matching: PhotosPickerFilter? = nil,
    preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .automatic,
    photoLibrary: PHPhotoLibrary = .shared()
  ) -> ModifiedContent<Self, PhotosPickerModifier> {
    modifier(PhotosPickerModifier(isPresented: isPresented, selection: selection, maxSelectionCount: maxSelectionCount, selectionBehavior: selectionBehavior, matching: matching, preferredItemEncoding: preferredItemEncoding, photoLibrary: photoLibrary))
  }
}

@_spi(Browser) public enum PhotosPickerRuntime {
  public static let selectionEvent = "photos-picker-selection"
  public static let cancelEvent = "photos-picker-cancel"
}

private extension Array where Element: Hashable {
  func deduplicated() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
