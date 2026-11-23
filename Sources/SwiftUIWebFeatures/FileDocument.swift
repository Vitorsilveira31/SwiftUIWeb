@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// SwiftUI-shaped file import/export APIs.  Browser file handles stay inside
// SwiftUIWebBrowser; application code receives URL values and byte/document
// values through this backend-neutral surface.

@_spi(Renderer) import SwiftUIWebTransferable
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

/// Foundation-free counterpart of Foundation.FileWrapper used by WASM and
/// Embedded builds.  Regular files cover the common SwiftUI FileDocument
/// path; directory wrappers are retained so document implementations can
/// remain source-compatible when they need a package-like export.
public struct FileWrapper: Hashable, Sendable {
  public let regularFileContents: Data?
  public let fileWrappers: [String: FileWrapper]?

  public init(regularFileWithContents contents: Data) {
    regularFileContents = contents
    fileWrappers = nil
  }

  public init(directoryWithFileWrappers wrappers: [String: FileWrapper]) {
    regularFileContents = nil
    fileWrappers = wrappers
  }
}

/// The configuration passed to a ``FileDocument`` initializer.
public struct FileDocumentReadConfiguration {
  public let file: FileWrapper
  public let contentType: UTType

  @_spi(Renderer) public init(file: FileWrapper, contentType: UTType = .data) {
    self.file = file
    self.contentType = contentType
  }
}

/// The configuration passed to a ``FileDocument`` writer.
public struct FileDocumentWriteConfiguration {
  public let contentType: UTType

  @_spi(Renderer) public init(contentType: UTType = .data) {
    self.contentType = contentType
  }
}

/// A SwiftUI-compatible document abstraction.  The associated configuration
/// defaults keep the usual ``ReadConfiguration``/``WriteConfiguration``
/// spellings source-compatible while allowing advanced hosts to specialize
/// them when needed.
@preconcurrency public protocol FileDocument {
  typealias ReadConfiguration = FileDocumentReadConfiguration
  typealias WriteConfiguration = FileDocumentWriteConfiguration

  static var readableContentTypes: [UTType] { get }
  static var writableContentTypes: [UTType] { get }
  init(configuration: Self.ReadConfiguration) throws
  func fileWrapper(configuration: Self.WriteConfiguration) throws -> FileWrapper
}

public extension FileDocument {
  static var writableContentTypes: [UTType] { readableContentTypes }
}

/// Extracts bytes from a regular file wrapper without requiring Foundation.
/// Directory wrappers intentionally return nil; callers can provide a custom
/// archive representation when exporting a package document.
@_spi(Renderer) public func swiftUIWebFileData(_ wrapper: FileWrapper) -> Data? {
  return wrapper.regularFileContents
}

/// Document and typed loading on top of the transfer runtime's file URLs. The URL
/// primitives (``SwiftUIWebFileRuntime/load(_:)``, ``SwiftUIWebFileRuntime/url(identifier:)``)
/// live in SwiftUIWebTransferable so the Transferable representations can use them.
@_spi(Renderer) public extension SwiftUIWebFileRuntime {
  static func loadData(_ url: URL) async throws -> Data? {
    try await load(url)?.data
  }

  static func loadTransferable<T: Transferable>(_ type: T.Type = T.self, from url: URL) async throws -> T? {
    guard let file = try await load(url) else { return nil }
    return try await T.importing(data: file.data, contentType: file.contentType)
  }

  /// Builds a document from an imported file using the same FileDocument
  /// initializer that native SwiftUI clients use.
  static func load<Document: FileDocument>(_ type: Document.Type, from url: URL) async throws -> Document? {
    guard let file = try await load(url) else { return nil }
    let wrapper = FileWrapper(regularFileWithContents: file.data)
    return try Document(configuration: FileDocumentReadConfiguration(file: wrapper, contentType: file.contentType))
  }
}

/// Browser-facing registration for exporter providers.  It remains a tiny
/// process-local registry so the Core API does not depend on JavaScript or the
/// DOM, while BrowserApp can perform the actual download at commit time.
@_spi(Browser) public enum FileExporterRuntime {
  public typealias Provider = () async throws -> SwiftUIWebTransferPayload
  @MainActor private static var providers: [String: Provider] = .init()
  private static let lock = _RuntimeLock()

  @MainActor public static func register(key: String, provider: @escaping Provider) {
    lock.withLock { providers[key] = provider }
  }

  @MainActor public static func remove(key: String) {
    lock.withLock { _ = providers.removeValue(forKey: key) }
  }

  @MainActor public static func export(key: String) async throws -> SwiftUIWebTransferPayload {
    guard let provider = lock.withLock({ providers[key] }) else {
      throw SwiftUIWebTransferError(.unavailable, message: "The file exporter is no longer available")
    }
    return try await provider()
  }
}

private func _swiftUIWebFileAccept(_ types: [UTType]) -> String? {
  let values = types.flatMap { type -> [String] in
    var result: [String] = []
    if let mime = type.preferredMIMEType, !mime.isEmpty { result.append(mime) }
    if let ext = type.preferredFilenameExtension, !ext.isEmpty { result.append("." + ext) }
    // Unknown UTIs are retained as a hint for hosts that understand them;
    // browsers ignore unsupported tokens without affecting selection.
    if result.isEmpty, !type.identifier.isEmpty { result.append(type.identifier) }
    return result
  }
  var seen = Set<String>()
  let unique = values.filter { seen.insert($0).inserted }
  return unique.isEmpty ? nil : unique.joined(separator: ",")
}

package nonisolated struct FileImporterModifier: ViewModifier {
  private let isPresented: Binding<Bool>
  private let allowedContentTypes: [UTType]
  private let allowsMultipleSelection: Bool
  private let completion: (Result<[URL], Error>) -> Void
  private let cancellation: (() -> Void)?

  package init(
    isPresented: Binding<Bool>,
    allowedContentTypes: [UTType],
    allowsMultipleSelection: Bool,
    onCompletion: @escaping (Result<[URL], Error>) -> Void,
    onCancellation: (() -> Void)? = nil
  ) {
    self.isPresented = isPresented
    self.allowedContentTypes = allowedContentTypes
    self.allowsMultipleSelection = allowsMultipleSelection
    completion = onCompletion
    cancellation = onCancellation
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if case .fragment = node.kind {
      let original = node.cloneSharingChildren(); node.kind = .element("div"); node.text = nil; node.children = [original]
    } else if case .text = node.kind {
      let original = node.cloneSharingChildren(); node.kind = .element("div"); node.text = nil; node.children = [original]
    }
    node.classes.append("file-importer")
    node.attributes["data-file-importer"] = "true"
    node.attributes["data-file-importer-presented"] = isPresented.wrappedValue ? "true" : "false"
    node.attributes["data-file-importer-multiple"] = allowsMultipleSelection ? "true" : "false"
    node.attributes["data-file-importer-types"] = allowedContentTypes.map { $0.identifier }.joined(separator: ",")
    if let accept = _swiftUIWebFileAccept(allowedContentTypes) { node.attributes["data-file-importer-accept"] = accept }
    node.events[FileImporterRuntime.event] = _EventHandler(name: FileImporterRuntime.event, action: { encoded in
      if encoded == FileImporterRuntime.cancelled {
        if let cancellation {
          cancellation()
        } else {
          completion(.failure(SwiftUIWebTransferError(.cancelled, message: "File selection was cancelled")))
        }
      } else if encoded.hasPrefix("success-inline:") {
        let raw = String(encoded.dropFirst("success-inline:".count))
        completion(_inlineFileResult(raw, prefix: "embedded-import-", invalidMessage: "Invalid embedded file payload").map { [$0] })
      } else if encoded.hasPrefix(FileImporterRuntime.successPrefix) {
        let ids = String(encoded.dropFirst(FileImporterRuntime.successPrefix.count)).split(separator: ",", omittingEmptySubsequences: true)
        completion(.success(ids.map { SwiftUIWebFileRuntime.url(identifier: String($0)) }))
      } else {
        let message = encoded.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "Unable to import file"
        completion(.failure(SwiftUIWebTransferError(.unavailable, message: message)))
      }
      isPresented.wrappedValue = false
    })
  }
}

package nonisolated struct FileExporterModifier<Document: FileDocument>: ViewModifier {
  private let isPresented: Binding<Bool>
  private let document: Document?
  private let contentType: UTType
  private let defaultFilename: String?
  private let completion: (Result<URL, Error>) -> Void
  private let cancellation: (() -> Void)?

  package init(isPresented: Binding<Bool>, document: Document?, contentType: UTType?, defaultFilename: String?, onCompletion: @escaping (Result<URL, Error>) -> Void, onCancellation: (() -> Void)? = nil) {
    self.isPresented = isPresented
    self.document = document
    self.contentType = contentType ?? Document.writableContentTypes.first ?? .data
    self.defaultFilename = defaultFilename
    completion = onCompletion
    cancellation = onCancellation
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if case .fragment = node.kind {
      let original = node.cloneSharingChildren(); node.kind = .element("div"); node.text = nil; node.children = [original]
    } else if case .text = node.kind {
      let original = node.cloneSharingChildren(); node.kind = .element("div"); node.text = nil; node.children = [original]
    }
    // The registry is process-wide while Fiber paths are only unique within
    // one tree; qualify the key with the owning store so independent trees
    // (several scenes, or concurrently rendered native hosts) never share an
    // exporter provider.
    let owner = String(UInt(bitPattern: ObjectIdentifier(context.stateStore).hashValue), radix: 36)
    let key = "\(owner):\(context._compactPathID)#file-exporter"
    FileExporterRuntime.register(key: key) { [document, contentType, defaultFilename] in
      guard let document else {
        throw SwiftUIWebTransferError(.unavailable, message: "There is no document to export")
      }
      let wrapper = try document.fileWrapper(configuration: FileDocumentWriteConfiguration(contentType: contentType))
      guard let data = swiftUIWebFileData(wrapper) else {
        throw SwiftUIWebTransferError(.invalidData, message: "The document did not produce a regular file")
      }
      return SwiftUIWebTransferPayload(data: data, contentType: contentType, suggestedFileName: defaultFilename)
    }
    node.classes.append("file-exporter")
    node.attributes["data-file-exporter"] = "true"
    node.attributes["data-file-exporter-key"] = key
    node.attributes["data-file-exporter-presented"] = isPresented.wrappedValue ? "true" : "false"
    node.attributes["data-file-exporter-content-type"] = contentType.identifier
    if let defaultFilename { node.attributes["data-file-exporter-filename"] = defaultFilename }
    if isPresented.wrappedValue, let document, let wrapper = try? document.fileWrapper(configuration: FileDocumentWriteConfiguration(contentType: contentType)), let bytes = swiftUIWebFileData(wrapper) {
      node.attributes["data-file-exporter-inline"] = Data(bytes).base64EncodedString()
    }
    node.events[FileExporterRuntime.event] = _EventHandler(name: FileExporterRuntime.event, action: { encoded in
      if encoded.hasPrefix("success-inline:") {
        let raw = String(encoded.dropFirst("success-inline:".count))
        completion(_inlineFileResult(raw, prefix: "embedded-export-", invalidMessage: "Invalid embedded export payload"))
      } else if encoded.hasPrefix(FileExporterRuntime.successPrefix) {
        let id = String(encoded.dropFirst(FileExporterRuntime.successPrefix.count))
        completion(.success(SwiftUIWebFileRuntime.url(identifier: id)))
      } else if encoded == FileExporterRuntime.cancelled {
        if let cancellation {
          cancellation()
        } else {
          completion(.failure(SwiftUIWebTransferError(.cancelled, message: "File export was cancelled")))
        }
      } else {
        let message = encoded.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "Unable to export file"
        completion(.failure(SwiftUIWebTransferError(.unavailable, message: message)))
      }
      isPresented.wrappedValue = false
    })
  }
}

@_spi(Browser) public enum FileImporterRuntime {
  public static let event = "fileImporter"
  public static let successPrefix = "success:"
  public static let cancelled = "cancelled"
}

@_spi(Browser) public extension FileExporterRuntime {
  static let event = "fileExporter"
  static let successPrefix = "success:"
  static let cancelled = "cancelled"
}

public extension View {
  /// Presents a file picker for one file of the allowed types.
  nonisolated func fileImporter(
    isPresented: Binding<Bool>,
    allowedContentTypes: [UTType],
    onCompletion: @escaping (Result<URL, Error>) -> Void
  ) -> some View {
    fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: false, onCompletion: { (result: Result<[URL], Error>) in
      switch result {
      case .success(let urls):
        if let first = urls.first {
          onCompletion(.success(first))
        } else {
          onCompletion(.failure(SwiftUIWebTransferError(.cancelled, message: "No file was selected")))
        }
      case .failure(let error):
        onCompletion(.failure(error))
      }
    })
  }

  /// Presents a file picker that can select several files.
  nonisolated func fileImporter(
    isPresented: Binding<Bool>,
    allowedContentTypes: [UTType],
    allowsMultipleSelection: Bool,
    onCompletion: @escaping (Result<[URL], Error>) -> Void
  ) -> some View {
    _modified(FileImporterModifier(isPresented: isPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: allowsMultipleSelection, onCompletion: onCompletion))
  }

  /// As ``fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)``, calling
  /// `onCancellation` (instead of `onCompletion` with an error) when the user dismisses the picker.
  nonisolated func fileImporter(
    isPresented: Binding<Bool>,
    allowedContentTypes: [UTType],
    allowsMultipleSelection: Bool,
    onCompletion: @escaping (Result<[URL], Error>) -> Void,
    onCancellation: @escaping () -> Void
  ) -> some View {
    _modified(FileImporterModifier(isPresented: isPresented, allowedContentTypes: allowedContentTypes, allowsMultipleSelection: allowsMultipleSelection, onCompletion: onCompletion, onCancellation: onCancellation))
  }

  /// Presents a save panel that writes `document` in `contentType`.
  nonisolated func fileExporter<Document: FileDocument>(
    isPresented: Binding<Bool>,
    document: Document?,
    contentType: UTType,
    defaultFilename: String? = nil,
    onCompletion: @escaping (Result<URL, Error>) -> Void
  ) -> some View {
    _modified(FileExporterModifier(isPresented: isPresented, document: document, contentType: contentType, defaultFilename: defaultFilename, onCompletion: onCompletion))
  }

  /// As ``fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)``, calling `onCancellation` when the user dismisses the panel.
  nonisolated func fileExporter<Document: FileDocument>(
    isPresented: Binding<Bool>,
    document: Document?,
    contentType: UTType,
    defaultFilename: String? = nil,
    onCompletion: @escaping (Result<URL, Error>) -> Void,
    onCancellation: @escaping () -> Void
  ) -> some View {
    _modified(FileExporterModifier(isPresented: isPresented, document: document, contentType: contentType, defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: onCancellation))
  }

  /// Presents a save panel whose content type is optional (the document's first writable type is used when nil).
  nonisolated func fileExporter<Document: FileDocument>(
    isPresented: Binding<Bool>,
    document: Document?,
    contentType: UTType? = nil,
    defaultFilename: String? = nil,
    onCompletion: @escaping (Result<URL, Error>) -> Void,
    onCancellation: (() -> Void)? = nil
  ) -> some View {
    _modified(FileExporterModifier(isPresented: isPresented, document: document, contentType: contentType, defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: onCancellation))
  }

  /// Presents a save panel for `document`, offering the listed content types.
  nonisolated func fileExporter<Document: FileDocument>(
    isPresented: Binding<Bool>,
    document: Document?,
    contentTypes: [UTType] = [],
    defaultFilename: String? = nil,
    onCompletion: @escaping (Result<URL, Error>) -> Void,
    onCancellation: @escaping () -> Void = {}
  ) -> some View {
    _modified(FileExporterModifier(isPresented: isPresented, document: document, contentType: contentTypes.first, defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: onCancellation))
  }

  /// Presents a panel that moves `file` to a location the person chooses.
  ///
  /// Chromium-based browsers write the file into a folder chosen with the File System Access
  /// API and remove it from the app's storage; other browsers download a copy and keep the
  /// source.
  nonisolated func fileMover(isPresented: Binding<Bool>, file: URL?, onCompletion: @escaping (Result<URL, Error>) -> Void) -> some View {
    _modified(FileMoverModifier(isPresented: isPresented, files: file.map { [$0] } ?? [], onCompletion: { result in
      switch result {
      case .success(let urls):
        if let first = urls.first {
          onCompletion(.success(first))
        } else {
          onCompletion(.failure(SwiftUIWebTransferError(.unavailable, message: "No file was moved")))
        }
      case .failure(let error):
        onCompletion(.failure(error))
      }
    }))
  }

  /// As ``fileMover(isPresented:file:onCompletion:)``, calling `onCancellation` (instead of
  /// `onCompletion` with an error) when the person dismisses the panel.
  nonisolated func fileMover(isPresented: Binding<Bool>, file: URL?, onCompletion: @escaping (Result<URL, Error>) -> Void, onCancellation: @escaping () -> Void) -> some View {
    _modified(FileMoverModifier(isPresented: isPresented, files: file.map { [$0] } ?? [], onCompletion: { result in
      switch result {
      case .success(let urls):
        if let first = urls.first {
          onCompletion(.success(first))
        } else {
          onCompletion(.failure(SwiftUIWebTransferError(.unavailable, message: "No file was moved")))
        }
      case .failure(let error):
        onCompletion(.failure(error))
      }
    }, onCancellation: onCancellation))
  }

  /// The multi-file form of ``fileMover(isPresented:file:onCompletion:)``.
  nonisolated func fileMover<C: Collection>(isPresented: Binding<Bool>, files: C, onCompletion: @escaping (Result<[URL], Error>) -> Void) -> some View where C.Element == URL {
    _modified(FileMoverModifier(isPresented: isPresented, files: Array(files), onCompletion: onCompletion))
  }

  /// As ``fileMover(isPresented:files:onCompletion:)``, calling `onCancellation` when the person dismisses the panel.
  nonisolated func fileMover<C: Collection>(isPresented: Binding<Bool>, files: C, onCompletion: @escaping (Result<[URL], Error>) -> Void, onCancellation: @escaping () -> Void) -> some View where C.Element == URL {
    _modified(FileMoverModifier(isPresented: isPresented, files: Array(files), onCompletion: onCompletion, onCancellation: onCancellation))
  }
}

@_spi(Browser) public enum FileMoverRuntime {
  public static let event = "fileMover"
  /// `moved:<id>,<base64 name>;...` when the files were written to the chosen location and
  /// the sources were removed from the app's storage.
  public static let movedPrefix = "moved:"
  /// `downloaded:<count>` when the browser could only hand out copies, so the sources stay.
  public static let downloadedPrefix = "downloaded:"
  public static let cancelled = "cancelled"
}

package nonisolated struct FileMoverModifier: ViewModifier {
  private let isPresented: Binding<Bool>
  private let files: [URL]
  private let completion: (Result<[URL], Error>) -> Void
  private let cancellation: (() -> Void)?

  package init(isPresented: Binding<Bool>, files: [URL], onCompletion: @escaping (Result<[URL], Error>) -> Void, onCancellation: (() -> Void)? = nil) {
    self.isPresented = isPresented
    self.files = files
    completion = onCompletion
    cancellation = onCancellation
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    if case .fragment = node.kind {
      let original = node.cloneSharingChildren(); node.kind = .element("div"); node.text = nil; node.children = [original]
    } else if case .text = node.kind {
      let original = node.cloneSharingChildren(); node.kind = .element("div"); node.text = nil; node.children = [original]
    }
    let presented = isPresented.wrappedValue && !files.isEmpty
    node.classes.append("file-mover")
    node.attributes["data-file-mover"] = "true"
    node.attributes["data-file-mover-presented"] = presented ? "true" : "false"
    node.attributes["data-file-mover-count"] = String(files.count)
    if presented {
      // One record per file: `base64(name),base64(content type),base64(bytes)`; `-` stands for
      // bytes the app does not hold in memory (a native path or a not yet read browser File).
      var records: [String] = []
      for url in files {
        var name = String(url.absoluteString.split(separator: "/", omittingEmptySubsequences: true).last ?? "file")
        var type = "application/octet-stream"
        var bytes = "-"
        if let identifier = SwiftUIWebFileRuntime.identifier(from: url), let payload = SwiftUIWebTransferRuntime._payloadIfLoaded(identifier: identifier) {
          if let suggested = payload.suggestedFileName, !suggested.isEmpty { name = suggested }
          type = payload.contentType.preferredMIMEType ?? type
          bytes = _fileTransferBase64Encode(Array(payload.data))
        }
        records.append(_fileTransferBase64Encode(Array(name.utf8)) + "," + _fileTransferBase64Encode(Array(type.utf8)) + "," + bytes)
      }
      node.attributes["data-file-mover-files"] = records.joined(separator: ";")
      node.attributes["data-file-mover-token"] = _fileMoverToken(for: files)
    }
    let sources = files
    node.events[FileMoverRuntime.event] = _EventHandler(name: FileMoverRuntime.event, action: { encoded in
      if encoded == FileMoverRuntime.cancelled {
        if let cancellation {
          cancellation()
        } else {
          completion(.failure(SwiftUIWebTransferError(.cancelled, message: "File move was cancelled")))
        }
      } else if encoded.hasPrefix(FileMoverRuntime.movedPrefix) {
        var entries = String(encoded.dropFirst(FileMoverRuntime.movedPrefix.count)).split(separator: ";", omittingEmptySubsequences: true)
        // The answer names the request it answers (`tok=<token>` first): a result meant for another mover, or for this
        // mover's earlier files, is refused.
        guard let first = entries.first, first == "tok=" + _fileMoverToken(for: sources) else {
          completion(.failure(SwiftUIWebTransferError(.invalidData, message: "Invalid file move result")))
          return
        }
        entries.removeFirst()
        var moved: [URL] = []
        var failed = entries.count != sources.count
        if !failed {
          for (index, entry) in entries.enumerated() {
            let fields = entry.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, let sourceID = SwiftUIWebFileRuntime.identifier(from: sources[index]),
                  let payload = SwiftUIWebTransferRuntime._payloadIfLoaded(identifier: sourceID),
                  let nameBytes = try? _fileTransferBase64Decode(String(fields[1])) else { failed = true; break }
            let id = String(fields[0])
            // The host mints moved ids as `moved-<random>`. An id that names an existing payload, or has another shape, is
            // refused so a result cannot replace a payload the app still holds.
            guard _isMintedMovedID(id) else { failed = true; break }
            SwiftUIWebTransferRuntime._register(identifier: id, payload: SwiftUIWebTransferPayload(data: payload.data, contentType: payload.contentType, suggestedFileName: String(decoding: nameBytes, as: UTF8.self)))
            moved.append(SwiftUIWebFileRuntime.url(identifier: id))
          }
        }
        if failed {
          completion(.failure(SwiftUIWebTransferError(.invalidData, message: "Invalid file move result")))
        } else {
          // The move is complete: the files now live at the new locations, so the old
          // identifiers stop resolving, as a moved file's old path does.
          for source in sources { if let id = SwiftUIWebFileRuntime.identifier(from: source) { SwiftUIWebTransferRuntime.remove(identifier: id) } }
          completion(.success(moved))
        }
      } else if encoded.hasPrefix(FileMoverRuntime.downloadedPrefix) {
        // The browser handed out copies and cannot confirm a move, so the sources stay valid.
        completion(.success(sources))
      } else {
        let message = encoded.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "Unable to move file"
        completion(.failure(SwiftUIWebTransferError(.unavailable, message: message)))
      }
      isPresented.wrappedValue = false
    })
  }
}

/// The largest file the browser hands over inline; a larger pick is refused, not loaded.
private let _inlineFileLimit = 64 * 1024 * 1024

/// Identifiers for payloads the browser hands over inline. A counter, not a hash of the payload, so two payloads never
/// share an identifier.
package final class _EmbeddedTransferIDs: @unchecked Sendable {
  package static let shared = _EmbeddedTransferIDs()
  private let lock = _RuntimeLock()
  private var counter: UInt64 = 0

  /// A fresh identifier: the counter keeps it unique, and a random 64-bit part keeps it unguessable, as the runtime's own
  /// identifiers are, so a `transfer-file://` URL taken from data cannot name an imported file it was not handed.
  package func next(_ prefix: String) -> String {
    var generator = SystemRandomNumberGenerator()
    let nonce = String(UInt64.random(in: UInt64.min ... UInt64.max, using: &generator), radix: 16)
    return lock.withLock {
      counter &+= 1
      return prefix + nonce + "-" + String(counter)
    }
  }
}

/// Parses `success-inline:<mime>:<name>:<base64>` (the wire the browser host writes; the mime type and name are
/// percent-encoded there, so a name containing `:` cannot split the fields) and registers the bytes as a file.
private func _inlineFileResult(_ raw: String, prefix: String, invalidMessage: String) -> Result<URL, Error> {
  let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
  guard parts.count == 3, let mime = _decodeInlineField(String(parts[0])), let name = _decodeInlineField(String(parts[1])),
        let bytes = try? _fileTransferBase64Decode(String(parts[2])) else {
    return .failure(SwiftUIWebTransferError(.invalidData, message: invalidMessage))
  }
  guard bytes.count <= _inlineFileLimit else {
    return .failure(SwiftUIWebTransferError(.invalidData, message: "The file is larger than 64 MiB"))
  }
  let id = _EmbeddedTransferIDs.shared.next(prefix)
  let type = UTType.from(mimeType: mime.isEmpty ? "application/octet-stream" : mime)
  // Kept with the bounded transient payloads: each import has its own id, so an unbounded registry would hold every file.
  SwiftUIWebTransferRuntime._registerTransient(identifier: id, payload: SwiftUIWebTransferPayload(data: Data(bytes), contentType: type, suggestedFileName: name))
  return .success(SwiftUIWebFileRuntime.url(identifier: id))
}

/// Decodes one percent-encoded field of the inline wire. `nil` for a malformed escape.
private func _decodeInlineField(_ text: String) -> String? {
  let bytes = Array(text.utf8)
  var output: [UInt8] = []
  output.reserveCapacity(bytes.count)
  var index = 0
  while index < bytes.count {
    if bytes[index] == UInt8(ascii: "%") {
      guard index + 2 < bytes.count, let high = _inlineHexValue(bytes[index + 1]), let low = _inlineHexValue(bytes[index + 2]) else {
        return nil
      }
      output.append(high << 4 | low)
      index += 3
    } else {
      output.append(bytes[index])
      index += 1
    }
  }
  return String(decoding: output, as: UTF8.self)
}

/// A per-process random key, so a mover token cannot be computed from the file ids alone.
private let _fileMoverSecret: UInt64 = {
  var generator = SystemRandomNumberGenerator()
  return generator.next()
}()

/// The token a mover's request carries and its answer must echo: a keyed hash of the files being moved, stable while
/// they stay the same, so every render of one request names it alike.
func _fileMoverToken(for files: [URL]) -> String {
  var hash = _fileMoverSecret ^ 0x9E37_79B9_7F4A_7C15
  func mix(_ byte: UInt64) {
    hash = (hash ^ byte) &* 0x0000_0100_0000_01B3
    hash ^= hash >> 29
  }
  for file in files {
    for byte in file.absoluteString.utf8 { mix(UInt64(byte)) }
    mix(0x1F)
  }
  var text = String(hash, radix: 16)
  while text.utf8.count < 16 { text = "0" + text }
  return text
}

private func _isMintedMovedID(_ id: String) -> Bool {
  let bytes = Array(id.utf8)
  guard bytes.count > 6, bytes.count <= 128, Array(id.utf8.prefix(6)) == Array("moved-".utf8) else { return false }
  guard bytes.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 }) else {
    return false
  }
  return SwiftUIWebTransferRuntime.metadata(for: id) == nil
}

private func _inlineHexValue(_ byte: UInt8) -> UInt8? {
  switch byte {
  case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
  case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
  case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
  default: return nil
  }
}

private func _fileTransferBase64Encode(_ bytes: [UInt8]) -> String {
  Data(bytes).base64EncodedString()
}

private func _fileTransferBase64Decode(_ value: String) throws -> [UInt8] {
  guard let bytes = Data(base64Encoded: value) else {
    throw SwiftUIWebTransferError(.invalidData, message: "Invalid file transfer base64")
  }
  return Array(bytes)
}
