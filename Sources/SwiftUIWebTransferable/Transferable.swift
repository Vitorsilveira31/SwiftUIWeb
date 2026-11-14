@_spi(Renderer) @_exported import SwiftUIWebLocking
// Shared, backend-neutral transfer infrastructure for Web/WASM.
// Browser File/Blob/DataTransfer values are deliberately never part of this
// module's API; browser hosts erase them to these Swift values at the edge.

@_exported import SwiftUIWebUniformTypeIdentifiers

/// Foundation's `Data`. A slice is a `Data` that keeps its base's indices (`data[2..<4].startIndex == 2`), as
/// Foundation's does; equality and hashing compare the bytes only.
public struct Data: RandomAccessCollection, MutableCollection, RangeReplaceableCollection, Hashable, Sendable {
  public typealias Element = UInt8
  public typealias Index = Int
  public typealias SubSequence = Data
  public typealias Indices = Range<Int>

  private var storage: [UInt8]
  /// The index of the first byte: zero, or the lower bound of the range this slice was cut from.
  private var offset: Int

  public init() { storage = []; offset = 0 }

  public init(_ elements: some Sequence<UInt8>) {
    storage = Array(elements)
    offset = 0
  }

  private init(storage: [UInt8], offset: Int) {
    self.storage = storage
    self.offset = offset
  }

  public var startIndex: Int { offset }
  public var endIndex: Int { offset + storage.count }
  public var indices: Range<Int> { startIndex ..< endIndex }
  public var count: Int { storage.count }

  public subscript(index: Data.Index) -> UInt8 {
    get { storage[index - offset] }
    set { storage[index - offset] = newValue }
  }

  public subscript(bounds: Range<Data.Index>) -> Data {
    get {
      precondition(bounds.lowerBound >= startIndex && bounds.upperBound <= endIndex, "Data slice out of range")
      return Data(storage: Array(storage[(bounds.lowerBound - offset) ..< (bounds.upperBound - offset)]), offset: bounds.lowerBound)
    }
    set { replaceSubrange(bounds, with: newValue) }
  }

  public subscript<R: RangeExpression>(rangeExpression: R) -> Data where R.Bound: FixedWidthInteger {
    get { self[_range(rangeExpression)] }
    set { self[_range(rangeExpression)] = newValue }
  }

  private func _range<R: RangeExpression>(_ expression: R) -> Range<Int> where R.Bound: FixedWidthInteger {
    let range = expression.relative(to: R.Bound(truncatingIfNeeded: startIndex) ..< R.Bound(truncatingIfNeeded: endIndex))
    return Int(range.lowerBound) ..< Int(range.upperBound)
  }

  public mutating func replaceSubrange(_ subrange: Range<Data.Index>, with newElements: some Collection<UInt8>) {
    storage.replaceSubrange((subrange.lowerBound - offset) ..< (subrange.upperBound - offset), with: newElements)
  }

  public static func == (lhs: Data, rhs: Data) -> Bool { lhs.storage == rhs.storage }

  public func hash(into hasher: inout Hasher) { hasher.combine(storage) }

  package func toArray() -> [UInt8] { storage }

  public func withUnsafeBytes<E: Error, ResultType: ~Copyable>(
    _ body: (UnsafeRawBufferPointer) throws(E) -> ResultType
  ) throws(E) -> ResultType {
    // Array's closure form is neither typed-throws nor noncopyable-result; the result and the error are carried out.
    var output: ResultType? = nil
    var failure: E? = nil
    storage.withUnsafeBytes { bytes in
      do throws(E) { output = try body(bytes) } catch { failure = error }
    }
    if let failure { throw failure }
    return output.take()!
  }

  public mutating func withUnsafeMutableBytes<E: Error, ResultType: ~Copyable>(
    _ body: (UnsafeMutableRawBufferPointer) throws(E) -> ResultType
  ) throws(E) -> ResultType {
    var output: ResultType? = nil
    var failure: E? = nil
    storage.withUnsafeMutableBytes { bytes in
      do throws(E) { output = try body(bytes) } catch { failure = error }
    }
    if let failure { throw failure }
    return output.take()!
  }

  package func utf8String() -> String {
    String(decoding: storage, as: UTF8.self)
  }

  /// `count` zero bytes.
  public init(count: Int) { storage = Array(repeating: 0, count: count); offset = 0 }

  /// Standard-alphabet base64, as Foundation reads it without options: groups of four characters, "=" only as the last
  /// one or two, no white space. nil otherwise, so two different texts never decode to the same bytes ("QQ==QQ==").
  public init?(base64Encoded string: String) {
    let input = Array(string.utf8)
    guard input.count % 4 == 0 else { return nil }
    var padding = 0
    if input.last == 61 { padding += 1 }
    if input.count >= 2, input[input.count - 2] == 61 { padding += 1 }
    var values: [UInt8] = []
    values.reserveCapacity(input.count)
    for (position, byte) in input.enumerated() {
      switch byte {
      case 65...90: values.append(byte - 65)
      case 97...122: values.append(byte - 71)
      case 48...57: values.append(byte + 4)
      case 43: values.append(62)
      case 47: values.append(63)
      case 61 where position >= input.count - padding: continue
      default: return nil
      }
    }
    var bytes: [UInt8] = []
    var index = 0
    while index + 1 < values.count {
      let c = index + 2 < values.count ? values[index + 2] : 0
      let d = index + 3 < values.count ? values[index + 3] : 0
      bytes.append(values[index] << 2 | values[index + 1] >> 4)
      if index + 2 < values.count { bytes.append(values[index + 1] << 4 | c >> 2) }
      if index + 3 < values.count { bytes.append(c << 6 | d) }
      index += 4
    }
    storage = bytes
    offset = 0
  }

  public func base64EncodedString() -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    guard !storage.isEmpty else { return "" }
    var result = ""
    result.reserveCapacity(((storage.count + 2) / 3) * 4)
    var index = 0
    while index < storage.count {
      let a = Int(storage[index]); index += 1
      let hasB = index < storage.count
      let b = hasB ? Int(storage[index]) : 0; if hasB { index += 1 }
      let hasC = index < storage.count
      let c = hasC ? Int(storage[index]) : 0; if hasC { index += 1 }
      result.append(alphabet[(a >> 2) & 0x3f])
      result.append(alphabet[((a & 0x03) << 4) | ((b >> 4) & 0x0f)])
      result.append(hasB ? alphabet[((b & 0x0f) << 2) | ((c >> 6) & 0x03)] : Character("="))
      result.append(hasC ? alphabet[c & 0x3f] : Character("="))
    }
    return result
  }

}

/// Foundation-free URL value for Embedded/WASI builds. It lives beside `Data`
/// because the transfer representations (`DataRepresentation`, `FileRepresentation`)
/// name it in their Apple-shaped signatures; Core re-exports it as `URL`.
public struct URL: Hashable, Sendable {
  public let absoluteString: String
  /// Foundation's failable initializer: `nil` for an empty string or one whose structure is not a URL (RFC 3986): a
  /// scheme with characters outside `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`, an IP-literal host without its
  /// closing bracket or with characters an IPv6 address cannot hold, or a port that is not a number. The string is kept
  /// as written; the URL performs no loading.
  public init?(string: String) {
    guard !string.isEmpty, _isStructurallyValidURL(Array(string.utf8)) else { return nil }
    absoluteString = string
  }
  /// A URL kept exactly as written, without validation; Foundation has no such initializer.
  package init(_ string: String) { absoluteString = string }
  /// Foundation's file URL: `file://` and the absolute path (a relative one resolves against the current directory,
  /// `/` in the virtual file system), with characters outside a URL path percent-encoded. A path naming a directory of
  /// the virtual file system ends in `/`, as Foundation's does for a directory on disk.
  public init(fileURLWithPath path: String) {
    self.init(fileURLWithPath: path, isDirectory: _VirtualFileSystem.shared.isDirectory(path.hasPrefix("/") ? path : "/" + path))
  }

  public init(fileURLWithPath path: String, isDirectory: Bool) {
    var absolute = path.hasPrefix("/") ? path : "/" + path
    if isDirectory, !absolute.hasSuffix("/") { absolute += "/" }
    absoluteString = "file://" + _percentEncodedURLPath(absolute)
  }
}

/// `path` with every byte outside Foundation's `urlPathAllowed` set (unreserved, sub-delims, `:`, `@`, `/`) as `%XX`.
private func _percentEncodedURLPath(_ path: String) -> String {
  let hex = Array("0123456789ABCDEF".utf8)
  var output: [UInt8] = []
  output.reserveCapacity(path.utf8.count)
  for byte in path.utf8 {
    switch byte {
    case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
         UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"),
         UInt8(ascii: "!"), UInt8(ascii: "$"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"),
         UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "="),
         UInt8(ascii: ":"), UInt8(ascii: "@"), UInt8(ascii: "/"):
      output.append(byte)
    default:
      output.append(UInt8(ascii: "%"))
      output.append(hex[Int(byte >> 4)])
      output.append(hex[Int(byte & 0x0f)])
    }
  }
  return String(decoding: output, as: UTF8.self)
}

public extension UTType {
  @_spi(Renderer) var mimeType: String { preferredMIMEType ?? identifier }
  @_spi(Renderer) var isImage: Bool { conforms(to: .image) }
  @_spi(Renderer) var isVideo: Bool { conforms(to: .movie) || conforms(to: .video) }
  @_spi(Renderer) static func from(mimeType: String) -> UTType {
    let normalized = mimeType.lowercased().split(separator: ";", maxSplits: 1).first.map(String.init) ?? mimeType.lowercased()
    if let known = UTType(mimeType: normalized) { return known }
    let parent: UTType? = normalized.hasPrefix("image/") ? .image : (normalized.hasPrefix("video/") ? .video : .data)
    return UTType(importedAs: normalized, conformingTo: parent)
  }
  @_spi(Renderer) static func from(filenameExtension: String) -> UTType {
    UTType(filenameExtension: filenameExtension) ?? .data
  }
}

@_spi(Renderer) public struct SwiftUIWebTransferError: Error, Hashable, Sendable, CustomStringConvertible {
  public enum Code: String, Hashable, Sendable { case unavailable, unsupportedContentType, invalidData, cancelled }
  public let code: Code
  public let message: String
  public init(_ code: Code, message: String? = nil) { self.code = code; self.message = message ?? code.rawValue }
  public var description: String { message }
}

@_spi(Renderer) public struct SwiftUIWebTransferPayload: Hashable, Sendable {
  public let data: Data
  public let contentType: UTType
  public let suggestedFileName: String?
  public init(data: Data, contentType: UTType, suggestedFileName: String? = nil) { self.data = data; self.contentType = contentType; self.suggestedFileName = suggestedFileName }
  public var bytes: Data { data }
}

@_spi(Renderer) public struct SwiftUIWebTransferMetadata: Hashable, Sendable {
  public let contentTypes: [UTType]
  public let suggestedFileName: String?
  public let size: Int64?
  public init(contentTypes: [UTType], suggestedFileName: String? = nil, size: Int64? = nil) { self.contentTypes = contentTypes; self.suggestedFileName = suggestedFileName; self.size = size }
  public init(contentType: UTType, suggestedFileName: String? = nil, size: Int64? = nil) { self.init(contentTypes: [contentType], suggestedFileName: suggestedFileName, size: size) }
  public var contentType: UTType? { contentTypes.first }
}

/// Browser-neutral file callback value. A browser adapter can keep its native
/// object alive in the runtime loader and only materialize this byte value on
/// demand, avoiding a second copy for metadata-only operations.
@_spi(Renderer) public struct SwiftUIWebTransferFile: Hashable, Sendable {
  public let data: Data
  public let contentType: UTType
  public let suggestedFileName: String?
  public init(data: Data, contentType: UTType = .data, suggestedFileName: String? = nil) { self.data = data; self.contentType = contentType; self.suggestedFileName = suggestedFileName }
}

/// Runtime file URLs. A `transfer-file://` URL names a payload registered with
/// ``SwiftUIWebTransferRuntime`` (a browser File/Blob or an in-memory value), so
/// file APIs hand applications an ordinary `URL` on every host. Other URLs are
/// native file paths, read only where the host has a file system.
@_spi(Renderer) public enum SwiftUIWebFileRuntime {
  private static let scheme = "transfer-file://"

  public static func url(identifier: String) -> URL {
    // The identifier is the host's; one URL validation refuses (a "[" in it) is still a name, not a trap.
    URL(string: scheme + identifier) ?? URL(scheme + identifier)
  }

  public static func identifier(from url: URL) -> String? {
    let text = url.absoluteString
    guard text.hasPrefix(scheme) else { return nil }
    let value = String(text.dropFirst(scheme.count))
    return value.isEmpty ? nil : value
  }

  /// Registers `payload` with the transfer runtime and returns the file URL that names it. The runtime keeps only the
  /// most recent such payloads; an older one is released when the cap is passed.
  public static func url(for payload: SwiftUIWebTransferPayload) -> URL {
    let identifier = SwiftUIWebTransferRuntime.makeIdentifier(channel: .fileImporter)
    SwiftUIWebTransferRuntime.registerTransient(identifier: identifier, payload: payload)
    return url(identifier: identifier)
  }

  /// Loads the bytes behind `url`. Picked and dropped files are read lazily through the runtime; `file://` URLs are
  /// read from the virtual file system.
  public static func load(_ url: URL) async throws -> SwiftUIWebTransferFile? {
    if let identifier = identifier(from: url) {
      guard let payload = try await SwiftUIWebTransferRuntime.load(identifier: identifier) else { return nil }
      return SwiftUIWebTransferFile(data: payload.data, contentType: payload.contentType, suggestedFileName: payload.suggestedFileName)
    }
    let path = _VirtualFileSystem.path(of: url)
    guard let data = _VirtualFileSystem.shared.file(at: path) else { return nil }
    let leaf = path.split(separator: "/").last.map(String.init)
    let contentType = leaf.flatMap { $0.split(separator: ".").count > 1 ? $0.split(separator: ".").last : nil }
      .flatMap { UTType(filenameExtension: String($0)) } ?? .data
    return SwiftUIWebTransferFile(data: data, contentType: contentType, suggestedFileName: leaf)
  }

  /// Writes an exported payload into `directory` (a directory of the virtual file system) under its suggested name.
  package static func write(_ payload: SwiftUIWebTransferPayload, into directory: URL) throws -> URL {
    let vfs = _VirtualFileSystem.shared
    let directoryPath = _VirtualFileSystem.path(of: directory)
    guard vfs.isDirectory(directoryPath) else { throw FileSystemError(reason: .notADirectory, path: directoryPath) }
    let target = (directoryPath == "/" ? "" : directoryPath) + "/" + exportLeafName(payload.suggestedFileName)
    try vfs.writeFile(payload.data, at: target)
    // The target is a decoded path; a literal `%` in a name must stay literal when the URL is read back.
    return URL(fileURLWithPath: target, isDirectory: false)
  }

  /// The single file-name component a suggested name contributes to an export. Directory components are dropped; a
  /// name with no usable leaf (empty, `.`, `..` or containing NUL) falls back to the default `item`.
  private static func exportLeafName(_ suggested: String?) -> String {
    guard let suggested, let leaf = suggested.split(separator: "/", omittingEmptySubsequences: true).last else {
      return "item"
    }
    let name = String(leaf)
    guard name != ".", name != "..", !name.utf8.contains(0) else { return "item" }
    return name
  }

}

/// A file delivered to a ``FileRepresentation`` importer. Browser imports are
/// backed by the transfer runtime through a `transfer-file://` URL, so the
/// value stays a plain URL exactly as CoreTransferable spells it.
public struct ReceivedTransferredFile: Sendable {
  public let file: URL
  public let isOriginalFile: Bool
  @_spi(Renderer) public init(file: URL, isOriginalFile: Bool = false) { self.file = file; self.isOriginalFile = isOriginalFile }
}

/// A file a ``FileRepresentation`` exporter hands to the transfer runtime. The
/// URL is either a runtime file URL or a native file path on hosts with a file system.
public struct SentTransferredFile: Sendable {
  public let file: URL
  public let allowAccessingOriginalFile: Bool
  public init(_ file: URL, allowAccessingOriginalFile: Bool = false) { self.file = file; self.allowAccessingOriginalFile = allowAccessingOriginalFile }
}

/// Leaf representations (`Body == Never`) have no body to evaluate.
@inline(never) func leafBodyUnavailable() -> Never { fatalError("Leaf transfer representations have no body") }

// MARK: Representations

/// A representation of a ``Transferable`` item. Its shape matches CoreTransferable:
/// composed representations provide `body`, while leaf representations
/// (``DataRepresentation``, ``FileRepresentation``, ``CodableRepresentation``,
/// ``ProxyRepresentation``) use `Body == Never`.
public protocol TransferRepresentation<Item>: Sendable {
  associatedtype Item: Transferable
  associatedtype Body
  @TransferRepresentationBuilder<Self.Item> var body: Self.Body { get }
  /// Underscored flattening hook used by the browser runtime. Applications never write it:
  /// composed representations inherit the default, which erases `body`.
  func _swiftUIWebErased() -> _AnyTransferRepresentation<Item>
}

public extension TransferRepresentation where Body: TransferRepresentation, Body.Item == Item {
  func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> { body._swiftUIWebErased() }
}

public extension TransferRepresentation where Body == Never {
  var body: Never { get { return leafBodyUnavailable() } }
}

/// Type-erased representation used by the runtime to flatten a builder result. Applications never name it.
public struct _AnyTransferRepresentation<Item: Transferable>: TransferRepresentation {
  public typealias Body = Never
  fileprivate struct Entry {
    let exported: [UTType]
    let imported: [UTType]
    let exporter: ((Item) async throws -> SwiftUIWebTransferPayload)?
    let importer: ((SwiftUIWebTransferPayload) async throws -> Item)?
  }
  fileprivate let entries: [Entry]

  public init<R: TransferRepresentation>(_ representation: R) where R.Item == Item { self = representation._swiftUIWebErased() }
  @_spi(Renderer) public init(exportedContentTypes: [UTType] = [], importedContentTypes: [UTType] = [], exporting: ((Item) async throws -> SwiftUIWebTransferPayload)? = nil, importing: ((SwiftUIWebTransferPayload) async throws -> Item)? = nil) {
    entries = [Entry(exported: exportedContentTypes, imported: importedContentTypes, exporter: exporting, importer: importing)]
  }
  fileprivate init(entries: [Entry]) { self.entries = entries }
  public static var unavailable: _AnyTransferRepresentation<Item> { _AnyTransferRepresentation(entries: []) }
  public var exportedContentTypes: [UTType] { entries.flatMap { entry in entry.exported }.deduplicated() }
  public var importedContentTypes: [UTType] { entries.flatMap { entry in entry.imported }.deduplicated() }
  public var hasExportRepresentation: Bool { entries.contains { $0.exporter != nil } }
  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> { self }

  /// Applies `transform` to every exporter; used by the representation modifiers.
  fileprivate func _mappingExporters(_ transform: @escaping (Entry, Item, SwiftUIWebTransferPayload) throws -> SwiftUIWebTransferPayload) -> _AnyTransferRepresentation<Item> {
    _AnyTransferRepresentation(entries: entries.map { entry in
      guard let exporter = entry.exporter else { return entry }
      return Entry(exported: entry.exported, imported: entry.imported, exporter: { value in
        try transform(entry, value, try await exporter(value))
      }, importer: entry.importer)
    })
  }

  /// Exports an item using the first compatible representation. Browser adapters use this
  /// method for clipboard, drag/drop, files, and sharing.
  @_spi(Renderer) public func export(_ value: Item, preferred: UTType? = nil) async throws -> SwiftUIWebTransferPayload {
    let candidates = entries.filter { $0.exporter != nil }
    guard !candidates.isEmpty else { throw SwiftUIWebTransferError(.unavailable, message: "No export representation is available") }
    let ordered = preferred.map { requested in candidates.sorted { a, b in
      let am = a.exported.contains { $0.conforms(to: requested) || requested.conforms(to: $0) }
      let bm = b.exported.contains { $0.conforms(to: requested) || requested.conforms(to: $0) }
      return am && !bm
    }} ?? candidates
    var last: Error?
    for entry in ordered { do { if let exporter = entry.exporter { return try await exporter(value) } } catch { last = error } }
    throw last ?? SwiftUIWebTransferError(.unavailable)
  }

  /// Exports every advertised format in representation order. Clipboard and drag/drop hosts use
  /// this to populate several MIME flavors; the single-format `export` path remains for files.
  @_spi(Renderer) public func exportAll(_ value: Item, preferredContentTypes: [UTType]? = nil) async throws -> [SwiftUIWebTransferPayload] {
    let requested = preferredContentTypes ?? exportedContentTypes
    if requested.isEmpty { return [try await export(value)] }
    var result: [SwiftUIWebTransferPayload] = []
    var seen = Set<UTType>()
    for type in requested {
      guard let payload = try? await export(value, preferred: type), seen.insert(payload.contentType).inserted else { continue }
      result.append(payload)
    }
    if result.isEmpty { result.append(try await export(value)) }
    return result
  }

  /// Imports a payload using the first compatible representation.
  @_spi(Renderer) public func `import`(_ payload: SwiftUIWebTransferPayload) async throws -> Item {
    let candidates = entries.filter { entry in
      guard entry.importer != nil else { return false }
      // A generic `.data` payload is accepted only by an importer whose content type conforms to `.data`; an entry that
      // declares no type does not take a payload of unknown type.
      if payload.contentType == .data { return entry.imported.contains { $0.conforms(to: .data) } }
      return entry.imported.isEmpty || entry.imported.contains { $0 == .data || $0.conforms(to: payload.contentType) || payload.contentType.conforms(to: $0) }
    }
    guard !candidates.isEmpty else { throw SwiftUIWebTransferError(.unsupportedContentType, message: "\(payload.contentType) is not supported by this transferable") }
    var last: Error?
    for entry in candidates { do { if let importer = entry.importer { return try await importer(payload) } } catch { last = error } }
    throw last ?? SwiftUIWebTransferError(.invalidData)
  }

  /// Exports `value` through the first compatible representation and imports it back. Underscored
  /// so that a representation can be checked without importing the SPI payload type.
  public func _roundTrip(_ value: Item) async throws -> Item {
    try await `import`(export(value))
  }
}
extension _AnyTransferRepresentation: @unchecked Sendable {}

/// Erases the item type of a representation so generic runtime helpers can hold any
/// `Transferable` representation without naming its opaque `body` type.
@_spi(Renderer) public struct SwiftUIWebAnyTransferRepresentation: @unchecked Sendable {
  public let exportedContentTypes: [UTType]
  public let importedContentTypes: [UTType]
  private let exportValue: (Any, UTType?) async throws -> SwiftUIWebTransferPayload
  private let importValue: (SwiftUIWebTransferPayload) async throws -> Any

  public init<R: TransferRepresentation>(_ representation: R) {
    let erased = representation._swiftUIWebErased()
    exportedContentTypes = erased.exportedContentTypes
    importedContentTypes = erased.importedContentTypes
    exportValue = { value, preferred in
      guard let value = value as? R.Item else { throw SwiftUIWebTransferError(.invalidData) }
      return try await erased.export(value, preferred: preferred)
    }
    importValue = { payload in try await erased.import(payload) }
  }

  public func export<Item>(_ value: Item, preferredContentType: UTType? = nil) async throws -> SwiftUIWebTransferPayload {
    try await exportValue(value, preferredContentType)
  }

  public func exportAll<Item>(_ value: Item, preferredContentTypes: [UTType]? = nil) async throws -> [SwiftUIWebTransferPayload] {
    let requested = preferredContentTypes ?? exportedContentTypes
    if requested.isEmpty { return [try await export(value)] }
    var result: [SwiftUIWebTransferPayload] = []
    var seen = Set<UTType>()
    for type in requested {
      guard let payload = try? await export(value, preferredContentType: type), seen.insert(payload.contentType).inserted else { continue }
      result.append(payload)
    }
    if result.isEmpty { result.append(try await export(value)) }
    return result
  }

  public func `import`<Item>(_ payload: SwiftUIWebTransferPayload, as: Item.Type = Item.self) async throws -> Item {
    guard let value = try await importValue(payload) as? Item else { throw SwiftUIWebTransferError(.invalidData) }
    return value
  }
}

/// A representation whose item is carried as raw bytes of one content type.
public struct DataRepresentation<Item: Transferable>: TransferRepresentation {
  public typealias Body = Never
  @_spi(Renderer) public let contentType: UTType
  private let exporting: (@Sendable (Item) async throws -> Data)?
  private let importing: (@Sendable (Data) async throws -> Item)?
  public init(contentType: UTType, exporting: @escaping @Sendable (Item) async throws -> Data, importing: @escaping @Sendable (Data) async throws -> Item) { self.contentType = contentType; self.exporting = exporting; self.importing = importing }
  public init(exportedContentType: UTType, exporting: @escaping @Sendable (Item) async throws -> Data) { contentType = exportedContentType; self.exporting = exporting; importing = nil }
  public init(importedContentType: UTType, importing: @escaping @Sendable (Data) async throws -> Item) { contentType = importedContentType; exporting = nil; self.importing = importing }
  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> {
    _AnyTransferRepresentation(exportedContentTypes: exporting == nil ? [] : [contentType], importedContentTypes: importing == nil ? [] : [contentType], exporting: exporting.map { exporter in { value in SwiftUIWebTransferPayload(data: try await exporter(value), contentType: self.contentType) } }, importing: importing.map { importer in { payload in try await importer(payload.data) } })
  }
}
extension DataRepresentation: @unchecked Sendable {}

#if hasFeature(Embedded)
/// Embedded Swift cannot reference Codable, so its representation encodes through EmbeddedCodable. Every other
/// build uses the encoder/decoder form below with the framework's JSON coders (JSONCoding.swift).
@preconcurrency public struct CodableRepresentation<Item: Transferable & EmbeddedCodable>: TransferRepresentation {
  public typealias Body = Never
  private let contentType: UTType
  public init(for: Item.Type = Item.self, contentType: UTType) { self.contentType = contentType }
  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> {
    _AnyTransferRepresentation(exportedContentTypes: [contentType], importedContentTypes: [contentType], exporting: { value in SwiftUIWebTransferPayload(data: try _EmbeddedJSONCodec.encode(value), contentType: self.contentType) }, importing: { payload in try _EmbeddedJSONCodec.decode(Item.self, from: payload.data) })
  }
}
extension CodableRepresentation: @unchecked Sendable {}
#else
/// The encoder protocol CodableRepresentation accepts. The framework's JSONEncoder conforms,
/// and so does any encoder whose output is `Data`.
public protocol _TopLevelEncoder {
  associatedtype Output
  func encode<T: Encodable>(_ value: T) throws -> Output
}

/// The decoder protocol CodableRepresentation accepts.
public protocol _TopLevelDecoder {
  associatedtype Input
  func decode<T: Decodable>(_ type: T.Type, from input: Input) throws -> T
}

extension JSONEncoder: _TopLevelEncoder {
  public typealias Output = Data
}

extension JSONDecoder: _TopLevelDecoder {
  public typealias Input = Data
}

/// A representation that encodes a Codable item with an encoder and decoder pair.
@preconcurrency public struct CodableRepresentation<Item: Codable & Transferable, Encoder: _TopLevelEncoder, Decoder: _TopLevelDecoder>: TransferRepresentation where Encoder.Output == Data, Decoder.Input == Data {
  public typealias Body = Never
  private let contentType: UTType
  private let encode: (Item) throws -> Data
  private let decode: (Data) throws -> Item

  public init(for: Item.Type = Item.self, contentType: UTType, encoder: Encoder, decoder: Decoder) {
    self.contentType = contentType
    encode = { value in try encoder.encode(value) }
    decode = { data in try decoder.decode(Item.self, from: data) }
  }

  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> {
    _AnyTransferRepresentation(exportedContentTypes: [contentType], importedContentTypes: [contentType], exporting: { value in SwiftUIWebTransferPayload(data: try self.encode(value), contentType: self.contentType) }, importing: { payload in try self.decode(payload.data) })
  }
}

extension CodableRepresentation where Encoder == JSONEncoder, Decoder == JSONDecoder {
  /// Encodes with the default JSON coders.
  public init(for: Item.Type = Item.self, contentType: UTType) {
    self.init(for: Item.self, contentType: contentType, encoder: JSONEncoder(), decoder: JSONDecoder())
  }
}
extension CodableRepresentation: @unchecked Sendable {}
#endif

/// A representation that moves an item as a file. Browser imports arrive as a runtime file URL.
public struct FileRepresentation<Item: Transferable>: TransferRepresentation {
  public typealias Body = Never
  @_spi(Renderer) public let contentType: UTType
  @_spi(Renderer) public let shouldAttemptToOpenInPlace: Bool
  @_spi(Renderer) public let shouldAllowToOpenInPlace: Bool
  private let exporting: (@Sendable (Item) async throws -> SentTransferredFile)?
  private let importing: (@Sendable (ReceivedTransferredFile) async throws -> Item)?

  public init(contentType: UTType, shouldAttemptToOpenInPlace: Bool = false, exporting: @escaping @Sendable (Item) async throws -> SentTransferredFile, importing: @escaping @Sendable (ReceivedTransferredFile) async throws -> Item) {
    self.contentType = contentType
    self.shouldAttemptToOpenInPlace = shouldAttemptToOpenInPlace
    shouldAllowToOpenInPlace = false
    self.exporting = exporting
    self.importing = importing
  }
  public init(exportedContentType: UTType, shouldAllowToOpenInPlace: Bool = false, exporting: @escaping @Sendable (Item) async throws -> SentTransferredFile) {
    contentType = exportedContentType
    shouldAttemptToOpenInPlace = false
    self.shouldAllowToOpenInPlace = shouldAllowToOpenInPlace
    self.exporting = exporting
    importing = nil
  }
  public init(importedContentType: UTType, shouldAttemptToOpenInPlace: Bool = false, importing: @escaping @Sendable (ReceivedTransferredFile) async throws -> Item) {
    contentType = importedContentType
    self.shouldAttemptToOpenInPlace = shouldAttemptToOpenInPlace
    shouldAllowToOpenInPlace = false
    exporting = nil
    self.importing = importing
  }
  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> {
    _AnyTransferRepresentation(exportedContentTypes: exporting == nil ? [] : [contentType], importedContentTypes: importing == nil ? [] : [contentType], exporting: exporting.map { exporter in { value in
      let sent = try await exporter(value)
      guard let file = try await SwiftUIWebFileRuntime.load(sent.file) else {
        throw SwiftUIWebTransferError(.unavailable, message: "The exported file is no longer available")
      }
      let actualType = file.contentType == .data ? self.contentType : file.contentType
      return SwiftUIWebTransferPayload(data: file.data, contentType: actualType, suggestedFileName: file.suggestedFileName)
    } }, importing: importing.map { importer in { payload in
      let url = SwiftUIWebFileRuntime.url(for: payload)
      return try await importer(ReceivedTransferredFile(file: url, isOriginalFile: self.shouldAttemptToOpenInPlace))
    } })
  }
}
extension FileRepresentation: @unchecked Sendable {}

/// A representation that stores an item through another transferable `Proxy` value.
public struct ProxyRepresentation<Item: Transferable, Proxy: Transferable>: TransferRepresentation {
  public typealias Body = Never
  private let exporting: (@Sendable (Item) async throws -> Proxy)?
  private let importing: (@Sendable (Proxy) async throws -> Item)?

  public init(exporting: @escaping @Sendable (Item) throws -> Proxy) { self.exporting = { value in try exporting(value) }; importing = nil }
  public init(exporting: @escaping @Sendable (Item) async throws -> Proxy) { self.exporting = exporting; importing = nil }
  public init(importing: @escaping @Sendable (Proxy) throws -> Item) { exporting = nil; self.importing = { value in try importing(value) } }
  public init(importing: @escaping @Sendable (Proxy) async throws -> Item) { exporting = nil; self.importing = importing }
  public init(exporting: @escaping @Sendable (Item) throws -> Proxy, importing: @escaping @Sendable (Proxy) throws -> Item) {
    self.exporting = { value in try exporting(value) }
    self.importing = { value in try importing(value) }
  }
  public init(exporting: @escaping @Sendable (Item) async throws -> Proxy, importing: @escaping @Sendable (Proxy) async throws -> Item) {
    self.exporting = exporting
    self.importing = importing
  }
  public init(exporting: @escaping @Sendable (Item) throws -> Proxy, importing: @escaping @Sendable (Proxy) async throws -> Item) {
    self.exporting = { value in try exporting(value) }
    self.importing = importing
  }
  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> {
    let proxy = SwiftUIWebAnyTransferRepresentation(Proxy._swiftUIWebRepresentation)
    return _AnyTransferRepresentation(exportedContentTypes: exporting == nil ? [] : proxy.exportedContentTypes, importedContentTypes: importing == nil ? [] : proxy.importedContentTypes, exporting: exporting.map { exporter in { value in try await proxy.export(try await exporter(value)) } }, importing: importing.map { importer in { payload in try await importer(try await proxy.`import`(payload, as: Proxy.self)) } })
  }
}
extension ProxyRepresentation: @unchecked Sendable {}

/// The representation produced by a builder block with more than one component.
public struct TupleTransferRepresentation<Item: Transferable, Value: Sendable>: TransferRepresentation {
  private let erased: _AnyTransferRepresentation<Item>
  @_spi(Renderer) public init(_ representations: [_AnyTransferRepresentation<Item>]) {
    erased = _AnyTransferRepresentation(entries: representations.flatMap { representation in representation.entries })
  }
  public var body: some TransferRepresentation<Item> { erased }
  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Item> { erased }
}
extension TupleTransferRepresentation: @unchecked Sendable {}

/// Builds a `transferRepresentation`. Like CoreTransferable, it accepts blocks of one to
/// ten representations; it has no `if`/`switch` support because Apple's builder has none either.
@resultBuilder public struct TransferRepresentationBuilder<Item: Transferable> {
  public static func buildExpression<R: TransferRepresentation>(_ expression: R) -> R where R.Item == Item { expression }
  public static func buildBlock<R: TransferRepresentation>(_ content: R) -> R where R.Item == Item { content }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation>(_ content1: C1, _ content2: C2) -> TupleTransferRepresentation<Item, (C1, C2)> where C1.Item == Item, C2.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3) -> TupleTransferRepresentation<Item, (C1, C2, C3)> where C1.Item == Item, C2.Item == Item, C3.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4, _ content5: C5) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item, C5.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4), _AnyTransferRepresentation(content5)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation, C6: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4, _ content5: C5, _ content6: C6) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5, C6)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item, C5.Item == Item, C6.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4), _AnyTransferRepresentation(content5), _AnyTransferRepresentation(content6)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation, C6: TransferRepresentation, C7: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4, _ content5: C5, _ content6: C6, _ content7: C7) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5, C6, C7)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item, C5.Item == Item, C6.Item == Item, C7.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4), _AnyTransferRepresentation(content5), _AnyTransferRepresentation(content6), _AnyTransferRepresentation(content7)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation, C6: TransferRepresentation, C7: TransferRepresentation, C8: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4, _ content5: C5, _ content6: C6, _ content7: C7, _ content8: C8) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5, C6, C7, C8)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item, C5.Item == Item, C6.Item == Item, C7.Item == Item, C8.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4), _AnyTransferRepresentation(content5), _AnyTransferRepresentation(content6), _AnyTransferRepresentation(content7), _AnyTransferRepresentation(content8)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation, C6: TransferRepresentation, C7: TransferRepresentation, C8: TransferRepresentation, C9: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4, _ content5: C5, _ content6: C6, _ content7: C7, _ content8: C8, _ content9: C9) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5, C6, C7, C8, C9)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item, C5.Item == Item, C6.Item == Item, C7.Item == Item, C8.Item == Item, C9.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4), _AnyTransferRepresentation(content5), _AnyTransferRepresentation(content6), _AnyTransferRepresentation(content7), _AnyTransferRepresentation(content8), _AnyTransferRepresentation(content9)])
  }
  public static func buildBlock<C1: TransferRepresentation, C2: TransferRepresentation, C3: TransferRepresentation, C4: TransferRepresentation, C5: TransferRepresentation, C6: TransferRepresentation, C7: TransferRepresentation, C8: TransferRepresentation, C9: TransferRepresentation, C10: TransferRepresentation>(_ content1: C1, _ content2: C2, _ content3: C3, _ content4: C4, _ content5: C5, _ content6: C6, _ content7: C7, _ content8: C8, _ content9: C9, _ content10: C10) -> TupleTransferRepresentation<Item, (C1, C2, C3, C4, C5, C6, C7, C8, C9, C10)> where C1.Item == Item, C2.Item == Item, C3.Item == Item, C4.Item == Item, C5.Item == Item, C6.Item == Item, C7.Item == Item, C8.Item == Item, C9.Item == Item, C10.Item == Item {
    TupleTransferRepresentation([_AnyTransferRepresentation(content1), _AnyTransferRepresentation(content2), _AnyTransferRepresentation(content3), _AnyTransferRepresentation(content4), _AnyTransferRepresentation(content5), _AnyTransferRepresentation(content6), _AnyTransferRepresentation(content7), _AnyTransferRepresentation(content8), _AnyTransferRepresentation(content9), _AnyTransferRepresentation(content10)])
  }
}

public extension TransferRepresentation {
  /// Visibility is a host hint on Web/WASM; the representation is unchanged.
  func visibility(_ visibility: TransferRepresentationVisibility) -> some TransferRepresentation<Item> { self }

  /// Exports only items that satisfy `condition`.
  func exportingCondition(_ condition: @escaping @Sendable (Item) -> Bool) -> _ConditionalTransferRepresentation<Self> {
    _ConditionalTransferRepresentation(base: self, condition: condition)
  }

  func suggestedFileName(_ fileName: String) -> some TransferRepresentation<Item> {
    _SuggestedFileNameTransferRepresentation(base: self, name: { _ in fileName })
  }

  func suggestedFileName(_ fileName: @escaping @Sendable (Item) -> String?) -> some TransferRepresentation<Item> {
    _SuggestedFileNameTransferRepresentation(base: self, name: fileName)
  }
}

/// The representation returned by ``TransferRepresentation/exportingCondition(_:)``.
public struct _ConditionalTransferRepresentation<Base: TransferRepresentation>: TransferRepresentation {
  public typealias Item = Base.Item
  public typealias Body = Never
  private let base: Base
  private let condition: @Sendable (Base.Item) -> Bool

  fileprivate init(base: Base, condition: @escaping @Sendable (Base.Item) -> Bool) {
    self.base = base
    self.condition = condition
  }

  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Base.Item> {
    let condition = self.condition
    return base._swiftUIWebErased()._exportingConditionally { value in
      guard condition(value) else { throw SwiftUIWebTransferError(.unavailable, message: "The value does not satisfy the export condition") }
    }
  }
}
extension _ConditionalTransferRepresentation: @unchecked Sendable {}

/// The representation returned by ``TransferRepresentation/suggestedFileName(_:)``.
public struct _SuggestedFileNameTransferRepresentation<Base: TransferRepresentation>: TransferRepresentation {
  public typealias Item = Base.Item
  public typealias Body = Never
  private let base: Base
  private let name: @Sendable (Base.Item) -> String?

  fileprivate init(base: Base, name: @escaping @Sendable (Base.Item) -> String?) {
    self.base = base
    self.name = name
  }

  public func _swiftUIWebErased() -> _AnyTransferRepresentation<Base.Item> {
    let name = self.name
    return base._swiftUIWebErased()._namingFiles(name)
  }
}
extension _SuggestedFileNameTransferRepresentation: @unchecked Sendable {}

extension _AnyTransferRepresentation {
  @_spi(Renderer) public func _exportingConditionally(_ check: @escaping (Item) throws -> Void) -> _AnyTransferRepresentation<Item> {
    _mappingExporters { _, value, payload in
      try check(value)
      return payload
    }
  }

  @_spi(Renderer) public func _namingFiles(_ name: @escaping (Item) -> String?) -> _AnyTransferRepresentation<Item> {
    _mappingExporters { _, value, payload in
      guard payload.suggestedFileName == nil, let fileName = name(value) else { return payload }
      return SwiftUIWebTransferPayload(data: payload.data, contentType: payload.contentType, suggestedFileName: fileName)
    }
  }
}

/// Visibility of an exported representation (CoreTransferable's shape).
public struct TransferRepresentationVisibility: Hashable, Sendable {
  private let rawValue: Int
  private init(_ rawValue: Int) { self.rawValue = rawValue }
  public static let all = TransferRepresentationVisibility(0)
  public static let team = TransferRepresentationVisibility(1)
  public static let ownProcess = TransferRepresentationVisibility(2)
}

// MARK: Transferable

@preconcurrency public protocol Transferable: Sendable {
  associatedtype Representation: TransferRepresentation
  @TransferRepresentationBuilder<Self> static var transferRepresentation: Representation { get }
}

/// Explicit spelling for applications that import Apple's CoreTransferable
/// alongside this package and therefore have two `Transferable` symbols.
@_spi(Renderer) public typealias SwiftUIWebTransferable = Transferable

public extension Transferable {
  /// The erased form of ``transferRepresentation``, which the runtime uses for every export and import.
  @_spi(Renderer) static var _swiftUIWebRepresentation: _AnyTransferRepresentation<Self> {
    _swiftUIWebRebind(Self.transferRepresentation, to: Self.self)
  }
}

/// Erases `representation` and names the result for `Item`.
///
/// SAFETY: `TransferRepresentationBuilder<Item>` accepts only representations whose `Item` is `Item`, so the
/// erased `_AnyTransferRepresentation<R.Item>` is `_AnyTransferRepresentation<Item>` in every value this is called
/// with. The two instantiations store identically laid-out closures and arrays, so the rebinding changes only the
/// static type. A `some TransferRepresentation` result cannot prove that equality to the compiler, which is why
/// the conversion is spelled here rather than in a `where` clause on `Transferable.Representation`.
@inline(__always)
func _swiftUIWebRebind<R: TransferRepresentation, Item: Transferable>(_ representation: R, to: Item.Type) -> _AnyTransferRepresentation<Item> {
  unsafeBitCast(representation._swiftUIWebErased(), to: _AnyTransferRepresentation<Item>.self)
}

public extension Transferable {
  static func exportedContentTypes(visibility: TransferRepresentationVisibility = .all) -> [UTType] { Self._swiftUIWebRepresentation.exportedContentTypes }
  func exportedContentTypes(_ visibility: TransferRepresentationVisibility = .all) -> [UTType] { Self.exportedContentTypes(visibility: visibility) }
  static func importedContentTypes() -> [UTType] { Self._swiftUIWebRepresentation.importedContentTypes }
  func importedContentTypes() -> [UTType] { Self.importedContentTypes() }

  @_spi(Renderer) func _swiftUIWebExport(preferredContentType: UTType? = nil) async throws -> SwiftUIWebTransferPayload {
    let payload = try await Self._swiftUIWebRepresentation.export(self, preferred: preferredContentType)
    guard payload.suggestedFileName == nil, let name = suggestedFilename else { return payload }
    return SwiftUIWebTransferPayload(data: payload.data, contentType: payload.contentType, suggestedFileName: name)
  }
  @_spi(Renderer) func _swiftUIWebExportAll(preferredContentTypes: [UTType]? = nil) async throws -> [SwiftUIWebTransferPayload] {
    let payloads = try await Self._swiftUIWebRepresentation.exportAll(self, preferredContentTypes: preferredContentTypes)
    guard let name = suggestedFilename else { return payloads }
    return payloads.map { payload in
      payload.suggestedFileName == nil
        ? SwiftUIWebTransferPayload(data: payload.data, contentType: payload.contentType, suggestedFileName: name)
        : payload
    }
  }
  func exported(as contentType: UTType?) async throws -> Data { try await _swiftUIWebExport(preferredContentType: contentType).data }

  /// Writes the exported value into `destinationDirectory`, a directory of the virtual file system.
  func export(to destinationDirectory: URL, contentType: UTType?) async throws -> URL {
    let payload = try await _swiftUIWebExport(preferredContentType: contentType)
    return try SwiftUIWebFileRuntime.write(payload, into: destinationDirectory)
  }

  /// Exports the value to a runtime file and passes its URL to `fileHandler`.
  func withExportedFile<Result>(contentType: UTType?, fileHandler: (URL) async throws -> Result) async throws -> Result {
    let payload = try await _swiftUIWebExport(preferredContentType: contentType)
    return try await fileHandler(SwiftUIWebFileRuntime.url(for: payload))
  }

  @_spi(Renderer) static func importing(data: Data, contentType: UTType? = nil) async throws -> Self {
    let type = contentType ?? importedContentTypes().first ?? .data
    return try await Self._swiftUIWebRepresentation.import(SwiftUIWebTransferPayload(data: data, contentType: type))
  }
  init(importing data: Data, contentType: UTType?) async throws { self = try await Self.importing(data: data, contentType: contentType) }

  /// Imports a file from `url`, reading it through the transfer runtime.
  init(importing file: URL, contentType: UTType?) async throws {
    guard let transferred = try await SwiftUIWebFileRuntime.load(file) else {
      throw SwiftUIWebTransferError(.unavailable, message: "The file is no longer available")
    }
    self = try await Self.importing(data: transferred.data, contentType: contentType ?? transferred.contentType)
  }

  var suggestedFilename: String? { nil }
}

// MARK: Channel-neutral runtime

@_spi(Renderer) public enum SwiftUIWebTransferChannel: String, Hashable, Sendable {
  case clipboard, dragAndDrop, fileImporter, fileExporter, photos, webShare, generic
  public static let pasteButton = clipboard
  public static let dropDestination = dragAndDrop
  public static let dragAndDropItem = dragAndDrop
  public static let dragDrop = dragAndDrop
  public static let fileImport = fileImporter
  public static let fileExport = fileExporter
  public static let file = fileExporter
  public static let photosUI = photos
  public static let share = webShare
}
@_spi(Renderer) public struct SwiftUIWebTransferItem: Hashable, Sendable {
  public let identifier: String
  public let channel: SwiftUIWebTransferChannel
  public let metadata: SwiftUIWebTransferMetadata
  public init(identifier: String, channel: SwiftUIWebTransferChannel = .generic, metadata: SwiftUIWebTransferMetadata = SwiftUIWebTransferMetadata(contentTypes: [])) { self.identifier = identifier; self.channel = channel; self.metadata = metadata }
  public func lease() -> SwiftUIWebTransferLease { SwiftUIWebTransferLease(identifier: identifier) }
}

/// Runtime state is shared by browser callbacks and application tasks. Hosts with threads run those tasks
/// concurrently, the browser on its one thread; the runtime lock is a mutex on the first and free on the second, so
/// the public transfer API need not be actor-isolated.
private final class SwiftUIWebTransferRuntimeLock: @unchecked Sendable {
  private let lock = _RuntimeLock()
  func withLock<T>(_ body: () -> T) -> T { lock.withLock(body) }
}

@_spi(Renderer) public enum SwiftUIWebTransferRuntime {
  public typealias Loader = @Sendable (String) async throws -> SwiftUIWebTransferPayload?
  public typealias Cleanup = @Sendable () -> Void
  private struct Record {
    var loader: Loader?
    var metadata: SwiftUIWebTransferMetadata
    var payload: SwiftUIWebTransferPayload?
    var cleanup: Cleanup?
    var leaseCount: Int
    /// A loader may finish after the same identifier has been replaced. The
    /// generation prevents that stale result from being cached into the new
    /// record (and, in the browser, from resurrecting a released File/Blob).
    let generation: UInt64
  }
  private struct InFlight {
    let token: UInt64
    let task: Task<SwiftUIWebTransferPayload?, Error>
  }
  private enum LoadPlan {
    case missing
    case payload(SwiftUIWebTransferPayload)
    case task(generation: UInt64, token: UInt64, task: Task<SwiftUIWebTransferPayload?, Error>)
  }
  private static let stateLock = SwiftUIWebTransferRuntimeLock()
  private final class State: @unchecked Sendable {
    var records: [String: Record] = [:]
    var inFlight: [String: InFlight] = [:]
    var counter: UInt64 = 0
    /// Identifiers registered by `SwiftUIWebFileRuntime.url(for:)`, oldest first.
    var transient: [String] = []
  }
  /// The most `url(for:)` payloads kept at once.
  private static let transientCap = 128
  /// The bytes the transient payloads may hold together (imported files are up to 64 MiB each).
  private static let transientByteCap = 256 * 1024 * 1024
  // Every access happens under `stateLock`.
  private static let state = State()
  private static func nextIdentifier(_ channel: SwiftUIWebTransferChannel) -> String {
    // A random 64-bit part makes an identifier unguessable: a `transfer-file://` URL that data supplies can name only a
    // payload whose identifier was handed out, not a sequential neighbour.
    var generator = SystemRandomNumberGenerator()
    let nonce = String(UInt64.random(in: UInt64.min...UInt64.max, using: &generator), radix: 16)
    return stateLock.withLock {
      state.counter &+= 1
      return "transfer-\(channel.rawValue)-\(nonce)-\(state.counter)"
    }
  }
  /// A payload kept for the app to read through a URL it was handed: the 128 most recent ones, and at most 256 MiB of
  /// them, stay. The oldest go first, but never one a lease holds (a provider still reading it).
  fileprivate static func registerTransient(identifier: String, payload: SwiftUIWebTransferPayload) {
    register(identifier: identifier, payload: payload)
    let evicted: [String] = stateLock.withLock {
      state.transient.append(identifier)
      var bytes = state.transient.reduce(0) { $0 &+ (state.records[$1]?.payload?.data.count ?? 0) }
      var evicted: [String] = []
      var index = 0
      while (state.transient.count - evicted.count > transientCap || bytes > transientByteCap), index < state.transient.count - 1 {
        let candidate = state.transient[index]
        if (state.records[candidate]?.leaseCount ?? 0) == 0 {
          evicted.append(candidate)
          bytes -= state.records[candidate]?.payload?.data.count ?? 0
        }
        index += 1
      }
      let gone = Set(evicted)
      state.transient.removeAll { gone.contains($0) }
      return evicted
    }
    for old in evicted { remove(identifier: old) }
  }
  public static func register(identifier: String, metadata: SwiftUIWebTransferMetadata, loader: @escaping Loader, cleanup: Cleanup? = nil) {
    let (previous, oldFlight) = stateLock.withLock { () -> (Record?, InFlight?) in
      state.counter &+= 1
      let previous = state.records.updateValue(Record(loader: loader, metadata: metadata, payload: nil, cleanup: cleanup, leaseCount: 0, generation: state.counter), forKey: identifier)
      return (previous, state.inFlight.removeValue(forKey: identifier))
    }
    oldFlight?.task.cancel()
    previous?.cleanup?()
  }
  /// Reserves a fresh identifier for a host-owned transfer on `channel`.
  @_spi(Renderer) public static func makeIdentifier(channel: SwiftUIWebTransferChannel) -> String { nextIdentifier(channel) }
  public static func register(identifier: String, payload: SwiftUIWebTransferPayload, cleanup: Cleanup? = nil) {
    let (previous, oldFlight) = stateLock.withLock { () -> (Record?, InFlight?) in
      state.counter &+= 1
      let previous = state.records.updateValue(Record(loader: nil, metadata: SwiftUIWebTransferMetadata(contentTypes: [payload.contentType], suggestedFileName: payload.suggestedFileName, size: Int64(payload.data.count)), payload: payload, cleanup: cleanup, leaseCount: 0, generation: state.counter), forKey: identifier)
      return (previous, state.inFlight.removeValue(forKey: identifier))
    }
    oldFlight?.task.cancel()
    previous?.cleanup?()
  }
  /// The payload of a record whose bytes are already in memory, without starting a loader.
  /// Records backed by a lazy browser File or Blob that has not been read yet report `nil`.
  @_spi(Browser) public static func _payloadIfLoaded(identifier: String) -> SwiftUIWebTransferPayload? { stateLock.withLock { state.records[identifier]?.payload } }
  public static func metadata(for identifier: String) -> SwiftUIWebTransferMetadata? { stateLock.withLock { state.records[identifier]?.metadata } }
  public static func load(identifier: String) async throws -> SwiftUIWebTransferPayload? {
#if !hasFeature(Embedded)
    try Task.checkCancellation()
#endif
    let plan = stateLock.withLock { () -> LoadPlan in
      guard let record = state.records[identifier] else { return .missing }
      if let payload = record.payload { return .payload(payload) }
      guard let loader = record.loader else { return .missing }
      if let existing = state.inFlight[identifier] {
        return .task(generation: record.generation, token: existing.token, task: existing.task)
      }
      let created = Task { try await loader(identifier) }
      state.counter &+= 1
      state.inFlight[identifier] = InFlight(token: state.counter, task: created)
      return .task(generation: record.generation, token: state.counter, task: created)
    }
    switch plan {
    case .missing: return nil
    case .payload(let payload): return payload
    case .task(let generation, let token, let task):
      defer {
        stateLock.withLock {
          if state.inFlight[identifier]?.token == token { state.inFlight.removeValue(forKey: identifier) }
        }
      }
      let payload = try await task.value
#if !hasFeature(Embedded)
      try Task.checkCancellation()
#endif
      return stateLock.withLock {
        // A host may release a resource while the async read is in flight. Do
        // not resurrect a removed object URL or File entry in that case.
        guard var current = state.records[identifier], current.generation == generation else { return nil }
        // Preserve a lease acquired while the asynchronous loader was running.
        var materialized = payload
        if let payload {
          // Metadata is available before a browser File/Blob is read. Carry its
          // filename into the materialized payload when the loader did not repeat
          // it, so FileRepresentation importers get the same value as native
          // providers without forcing hosts to duplicate metadata logic.
          if payload.suggestedFileName == nil, let name = current.metadata.suggestedFileName {
            materialized = SwiftUIWebTransferPayload(data: payload.data, contentType: payload.contentType, suggestedFileName: name)
          }
          current.payload = materialized
          let types = current.metadata.contentTypes.isEmpty ? [payload.contentType] : current.metadata.contentTypes
          let size = current.metadata.size ?? Int64(payload.data.count)
          if types != current.metadata.contentTypes || size != current.metadata.size || (current.metadata.suggestedFileName == nil && payload.suggestedFileName != nil) {
            current.metadata = SwiftUIWebTransferMetadata(contentTypes: types, suggestedFileName: current.metadata.suggestedFileName ?? payload.suggestedFileName, size: size)
          }
        } else {
          current.payload = nil
        }
        state.records[identifier] = current
        return materialized
      }
    }
  }
  public static func export<T: Transferable>(_ value: T, channel: SwiftUIWebTransferChannel = .generic, preferredContentType: UTType? = nil) async throws -> SwiftUIWebTransferItem { let payload = try await value._swiftUIWebExport(preferredContentType: preferredContentType); let identifier = nextIdentifier(channel); register(identifier: identifier, payload: payload); return SwiftUIWebTransferItem(identifier: identifier, channel: channel, metadata: SwiftUIWebTransferMetadata(contentTypes: [payload.contentType], suggestedFileName: payload.suggestedFileName, size: Int64(payload.data.count))) }
  public static func export<T: Transferable>(_ value: T, for channel: SwiftUIWebTransferChannel, preferredContentType: UTType? = nil) async throws -> SwiftUIWebTransferItem { try await export(value, channel: channel, preferredContentType: preferredContentType) }
  public static func load<T: Transferable>(_ item: SwiftUIWebTransferItem, as type: T.Type = T.self) async throws -> T? { guard let payload = try await load(identifier: item.identifier) else { return nil }; return try await SwiftUIWebAnyTransferRepresentation(T._swiftUIWebRepresentation).`import`(payload, as: T.self) }
  public static func load<T: Transferable>(identifier: String, as type: T.Type = T.self) async throws -> T? { guard let payload = try await load(identifier: identifier) else { return nil }; return try await SwiftUIWebAnyTransferRepresentation(T._swiftUIWebRepresentation).`import`(payload, as: T.self) }
  public static func exportPayloads<T: Transferable>(_ value: T, preferredContentTypes: [UTType]? = nil) async throws -> [SwiftUIWebTransferPayload] { try await value._swiftUIWebExportAll(preferredContentTypes: preferredContentTypes) }
  fileprivate static func retainLease(identifier: String) -> UInt64? {
    stateLock.withLock {
      guard var record = state.records[identifier] else { return nil }
      record.leaseCount += 1
      state.records[identifier] = record
      return record.generation
    }
  }
  fileprivate static func releaseLease(identifier: String, generation: UInt64?) {
    let shouldRemove = stateLock.withLock { () -> Bool in
      guard let generation, var record = state.records[identifier], record.generation == generation else { return false }
      record.leaseCount = max(0, record.leaseCount - 1)
      state.records[identifier] = record
      return record.leaseCount == 0
    }
    if shouldRemove { remove(identifier: identifier) }
  }
  public static func remove(identifier: String) {
    let (record, flight) = stateLock.withLock { () -> (Record?, InFlight?) in
      (state.records.removeValue(forKey: identifier), state.inFlight.removeValue(forKey: identifier))
    }
    flight?.task.cancel()
    record?.cleanup?()
  }
  /// Drops a host-owned transfer only when no PhotosPickerItem (or other
  /// lease) still references it. Browser hosts use this when a picker input is
  /// recycled; forcing `remove` there would invalidate an item that the
  /// application intentionally kept in state.
  public static func removeIfUnleased(identifier: String) {
    let removed: (Record?, InFlight?) = stateLock.withLock {
      guard state.records[identifier]?.leaseCount == 0 else { return (nil, nil) }
      return (state.records.removeValue(forKey: identifier), state.inFlight.removeValue(forKey: identifier))
    }
    removed.1?.task.cancel()
    removed.0?.cleanup?()
  }
  public static func remove(_ item: SwiftUIWebTransferItem) { remove(identifier: item.identifier) }
  public static func release(identifier: String) { remove(identifier: identifier) }
  @_spi(Browser) public static func _register(identifier: String, metadata: SwiftUIWebTransferMetadata, loader: @escaping Loader, cleanup: Cleanup? = nil) { register(identifier: identifier, metadata: metadata, loader: loader, cleanup: cleanup) }
  @_spi(Browser) public static func _register(identifier: String, payload: SwiftUIWebTransferPayload, cleanup: Cleanup? = nil) { register(identifier: identifier, payload: payload, cleanup: cleanup) }
  /// A payload the page handed over (an imported file, pasted text), kept with the bounded transient ones.
  @_spi(Browser) public static func _registerTransient(identifier: String, payload: SwiftUIWebTransferPayload) { registerTransient(identifier: identifier, payload: payload) }
}

@_spi(Renderer) public final class SwiftUIWebTransferLease: @unchecked Sendable {
  public let identifier: String
  private let generation: UInt64?
  public init(identifier: String) { self.identifier = identifier; generation = SwiftUIWebTransferRuntime.retainLease(identifier: identifier) }
  deinit { SwiftUIWebTransferRuntime.releaseLease(identifier: identifier, generation: generation) }
}

/// Leases compare by identity, so a provider's synthesized `Hashable` conformance (which Apple's
/// `NSItemProvider` gets from `NSObject`) compares the provider's own lease, not its contents.
extension SwiftUIWebTransferLease: Hashable {
  public static func == (lhs: SwiftUIWebTransferLease, rhs: SwiftUIWebTransferLease) -> Bool { lhs === rhs }
  public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension Data: Transferable {
  public typealias Representation = DataRepresentation<Data>
  public static var transferRepresentation: DataRepresentation<Data> { DataRepresentation(contentType: UTType.data, exporting: { $0 }, importing: { $0 }) }
}

extension String: Transferable {
  @_spi(Renderer) public typealias Representation = DataRepresentation<String>
  @_spi(Renderer) public static var transferRepresentation: DataRepresentation<String> { DataRepresentation(contentType: UTType.utf8PlainText, exporting: { Data($0.utf8) }, importing: { String(decoding: $0, as: UTF8.self) }) }
}

private extension Array where Element: Hashable {
  func deduplicated() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

/// The structural checks `URL(string:)` applies (see its documentation).
private func _isStructurallyValidURL(_ bytes: [UInt8]) -> Bool {
  func isAlpha(_ byte: UInt8) -> Bool { (0x41...0x5a).contains(byte) || (0x61...0x7a).contains(byte) }
  func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
  let colon = UInt8(ascii: ":"), slash = UInt8(ascii: "/"), question = UInt8(ascii: "?"), hash = UInt8(ascii: "#")
  // A scheme is the text before the first ":" that comes before any "/", "?" or "#"; without one the string is a
  // relative reference and only its characters matter.
  var index = 0
  if let schemeEnd = bytes.firstIndex(where: { $0 == colon || $0 == slash || $0 == question || $0 == hash }),
     bytes[schemeEnd] == colon {
    let scheme = bytes[..<schemeEnd]
    guard let first = scheme.first, isAlpha(first),
          scheme.allSatisfy({ isAlpha($0) || isDigit($0) || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: ".") })
    else { return false }
    index = schemeEnd + 1
  }
  // The authority follows "//" and runs to the next "/", "?" or "#".
  guard index + 1 < bytes.count, bytes[index] == slash, bytes[index + 1] == slash else { return true }
  let authorityStart = index + 2
  let authorityEnd = bytes[authorityStart...].firstIndex(where: { $0 == slash || $0 == question || $0 == hash }) ?? bytes.count
  var host = bytes[authorityStart..<authorityEnd]
  if let at = host.lastIndex(of: UInt8(ascii: "@")) { host = host[(at + 1)...] }
  var port: ArraySlice<UInt8> = []
  if host.first == UInt8(ascii: "[") {
    guard let close = host.firstIndex(of: UInt8(ascii: "]")) else { return false }
    let literal = host[(host.startIndex + 1)..<close]
    let isHex: (UInt8) -> Bool = { isDigit($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0) }
    guard !literal.isEmpty,
          literal.allSatisfy({ isHex($0) || $0 == colon || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "v") }) else {
      return false
    }
    let rest = host[(close + 1)...]
    if let first = rest.first {
      guard first == colon else { return false }
      port = rest.dropFirst()
    }
  } else if let lastColon = host.lastIndex(of: colon) {
    port = host[(lastColon + 1)...]
  }
  return port.allSatisfy(isDigit)
}
