// A small, Foundation-free subset of UniformTypeIdentifiers, the one UTType on every host.
//
// The browser has the same three pieces of information that callers normally
// need from UTType: an identifier, a MIME type, and a filename extension.  The
// registry below intentionally stays private to this module.  Keeping the
// browser's MIME aliases here means higher-level SwiftUIWeb APIs can deal in
// UTType values without depending on browser implementation details.

/// The tag classes understood by ``UTType``.
public struct UTTagClass: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let filenameExtension = UTTagClass(rawValue: "public.filename-extension")
  @_spi(Renderer) public static let MIMEType = UTTagClass(rawValue: "public.mime-type")

  /// Lowercase spelling for code that follows Swift naming conventions.
  public static let mimeType = MIMEType
}

/// A lightweight, WebAssembly-safe representation of a uniform type.
///
/// ``UTType`` deliberately has no Foundation or browser runtime dependency.
/// Unknown identifiers are still valid types; they simply have no registered
/// MIME/extension metadata and do not infer conformance beyond their own
/// identifier.
public struct UTType: Hashable, Sendable, CustomStringConvertible {
  public let identifier: String

  private let isCustomDeclaration: Bool
  private let declaredParents: [String]
  private let declaredMIMEType: String?
  private let declaredFilenameExtension: String?

  /// Creates a type from a UTI-style identifier.
  public init(_ identifier: String) {
    self.identifier = identifier
    isCustomDeclaration = false
    declaredParents = []
    declaredMIMEType = nil
    declaredFilenameExtension = nil
  }

  /// Compatibility initializer used by the original SwiftUIWeb transfer
  /// value. Metadata remains local to this value, while equality continues to
  /// follow the UTI identifier as it does for Foundation's UTType.
  @_spi(Renderer) public init(identifier: String, mimeType: String? = nil, filenameExtension: String? = nil) {
    self.init(identifier: identifier, parents: [], mimeType: mimeType, filenameExtension: filenameExtension)
  }

  private init(
    identifier: String,
    parents: [String] = [],
    mimeType: String? = nil,
    filenameExtension: String? = nil,
    isCustomDeclaration: Bool = false
  ) {
    self.identifier = identifier
    self.isCustomDeclaration = isCustomDeclaration
    declaredParents = parents
    declaredMIMEType = mimeType
    declaredFilenameExtension = filenameExtension
  }

  /// Creates a type from a browser MIME type.
  ///
  /// MIME matching is case-insensitive and ignores parameters such as
  /// ``; charset=utf-8``.  The lookup accepts the common aliases emitted by
  /// browsers, while the returned type always uses its canonical identifier.
  public init?(mimeType: String) {
    let normalized = UTTypeRegistry.normalizeMIMEType(mimeType)
    // A wildcard such as `video/*` names a family of types, not one type: Apple returns nil for it.
    guard !normalized.contains("*"), let identifier = UTTypeRegistry.identifier(forMIMEType: normalized) else {
      return nil
    }
    self.init(identifier)
  }

  /// Creates a type from a filename extension.
  ///
  /// A leading dot is accepted as a convenience (``.png`` and ``png`` are
  /// equivalent).  When a filename is passed accidentally, the final path
  /// component and its final extension are used.
  public init?(filenameExtension: String) {
    let normalized = UTTypeRegistry.normalizeFilenameExtension(filenameExtension)
    guard let identifier = UTTypeRegistry.identifier(forFilenameExtension: normalized) else {
      return nil
    }
    self.init(identifier)
  }

  /// Creates a type from a Uniform Type tag and optionally restricts it to a
  /// subtype of ``supertype``.
  public init?(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType? = nil) {
    let resolved: UTType?
    switch tagClass {
    case .filenameExtension:
      resolved = UTType(filenameExtension: tag)
    case .MIMEType:
      resolved = UTType(mimeType: tag)
    default:
      resolved = nil
    }

    guard let resolved else { return nil }
    if let supertype, !resolved.conforms(to: supertype) {
      return nil
    }
    self = resolved
  }

  /// Declares a custom exported type while retaining its immediate
  /// conformance relationship.  This mirrors the useful part of Foundation's
  /// exported/imported UTI initializers without a process-wide registration
  /// database.
  public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
    self.init(
      identifier: identifier,
      parents: parentType.map { [$0.identifier] } ?? [],
      isCustomDeclaration: true
    )
  }

  /// Declares a custom imported type while retaining its immediate
  /// conformance relationship.
  public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
    self.init(
      identifier: identifier,
      parents: parentType.map { [$0.identifier] } ?? [],
      isCustomDeclaration: true
    )
  }

  public var description: String { identifier }

  // UTType identity is the identifier. Metadata attached by the exported or
  // imported convenience initializers only supplies local conformance while
  // the value is in hand; it must not make two values with the same UTI
  // compare differently.
  public static func == (lhs: UTType, rhs: UTType) -> Bool {
    lhs.identifier == rhs.identifier
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(identifier)
  }

  /// The preferred MIME type for this type, when one is registered.
  public var preferredMIMEType: String? {
    declaredMIMEType ?? UTTypeRegistry.definition(for: identifier)?.mimeType
  }

  /// The preferred filename extension for this type, when one is registered.
  public var preferredFilenameExtension: String? {
    declaredFilenameExtension ?? UTTypeRegistry.definition(for: identifier)?.filenameExtension
  }

  /// Short compatibility spelling used by SwiftUIWeb's transfer metadata.
  @_spi(Renderer) public var filenameExtension: String? { preferredFilenameExtension }

  /// All registered tags for this type.
  public var tags: [UTTagClass: [String]] {
    let definition = UTTypeRegistry.definition(for: identifier)
    var result: [UTTagClass: [String]] = .init()

    if let mimeType = preferredMIMEType {
      result[.MIMEType] = [mimeType] + (definition?.mimeAliases ?? [])
    }
    if let filenameExtension = preferredFilenameExtension {
      result[.filenameExtension] = [filenameExtension] + (definition?.filenameAliases ?? [])
    }
    return result
  }

  /// Returns true when this type is equal to, or derives from, ``type``.
  public func conforms(to type: UTType) -> Bool {
    if identifier == type.identifier { return true }

    var pending = [identifier]
    var visited = Set<String>()

    while let current = pending.popLast() {
      guard visited.insert(current).inserted else { continue }

      let parents: [String]
      if current == identifier, !declaredParents.isEmpty {
        parents = declaredParents
      } else {
        parents = UTTypeRegistry.definition(for: current)?.parents ?? []
      }

      if parents.contains(type.identifier) {
        return true
      }
      pending.append(contentsOf: parents)
    }

    return false
  }

  /// Whether this type has a declaration in the built-in registry or was
  /// created with one of the custom exported/imported initializers.
  public var isDeclared: Bool {
    isCustomDeclaration || UTTypeRegistry.definition(for: identifier) != nil
  }

  /// Whether this identifier is not one of the built-in declarations.
  public var isDynamic: Bool { !isDeclared }

  /// Whether the identifier belongs to the public UTI namespace.
  public var isPublic: Bool { identifier.hasPrefix("public.") }

  /// Reference types are not modeled by this lightweight registry.
  @_spi(Renderer) public var isReference: Bool { false }

  // MARK: Common system types

  public static let item = UTType("public.item")
  public static let content = UTType("public.content")
  public static let compositeContent = UTType("public.composite-content")
  public static let data = UTType("public.data")
  public static let directory = UTType("public.directory")

  public static let text = UTType("public.text")
  public static let plainText = UTType("public.plain-text")
  public static let utf8PlainText = UTType("public.utf8-plain-text")
  public static let html = UTType("public.html")
  public static let xml = UTType("public.xml")
  public static let json = UTType("public.json")
  public static let rtf = UTType("public.rtf")
  public static let delimitedText = UTType("public.delimited-values-text")
  public static let commaSeparatedText = UTType("public.comma-separated-values-text")
  public static let tabSeparatedText = UTType("public.tab-separated-values-text")

  public static let url = UTType("public.url")
  public static let fileURL = UTType("public.file-url")

  public static let image = UTType("public.image")
  public static let jpeg = UTType("public.jpeg")
  public static let png = UTType("public.png")
  public static let heic = UTType("public.heic")
  public static let webP = UTType("org.webmproject.webp")
  public static let gif = UTType("com.compuserve.gif")
  public static let svg = UTType("public.svg-image")

  public static let audiovisualContent = UTType("public.audiovisual-content")
  public static let movie = UTType("public.movie")
  public static let quickTimeMovie = UTType("public.movie")
  public static let video = UTType("public.video")
  @_spi(Renderer) public static let mpeg4 = UTType("public.mpeg-4")
  /// An MPEG-4 movie (`.mp4`), as Apple's `UTType.mpeg4Movie`.
  public static let mpeg4Movie = UTType("public.mpeg-4")
  public static let audio = UTType("public.audio")

  public static let pdf = UTType("com.adobe.pdf")
  public static let archive = UTType("public.archive")
  public static let zip = UTType("public.zip-archive")
  public static let gzip = UTType("org.gnu.gnu-zip-archive")
  @_spi(Renderer) public static let tar = UTType("public.tar-archive")

  // These aliases make common Transferable declarations pleasant to use
  // while keeping the requested core registry small.
  public static let webArchive = UTType("com.apple.webarchive")
  public static let sourceCode = UTType("public.source-code")
}

// MARK: - Private browser registry

private enum UTTypeRegistry {
  struct Definition: Sendable {
    let parents: [String]
    let mimeType: String?
    let filenameExtension: String?
    let mimeAliases: [String]
    let filenameAliases: [String]

    init(
      parents: [String] = [],
      mimeType: String? = nil,
      filenameExtension: String? = nil,
      mimeAliases: [String] = [],
      filenameAliases: [String] = []
    ) {
      self.parents = parents
      self.mimeType = mimeType
      self.filenameExtension = filenameExtension
      self.mimeAliases = mimeAliases
      self.filenameAliases = filenameAliases
    }
  }

  static func definition(for identifier: String) -> Definition? {
    definitions[identifier]
  }

  static func normalizeMIMEType(_ value: String) -> String {
    guard let withoutParameters = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first else {
      return ""
    }
    return trimWhitespace(String(withoutParameters)).lowercased()
  }

  static func normalizeFilenameExtension(_ value: String) -> String {
    var normalized = trimWhitespace(value).lowercased()
    if let slash = normalized.lastIndex(of: "/") {
      normalized = String(normalized[normalized.index(after: slash)...])
    }
    while normalized.first == "." {
      normalized.removeFirst()
    }
    if let dot = normalized.lastIndex(of: ".") {
      normalized = String(normalized[normalized.index(after: dot)...])
    }
    return normalized
  }

  private static func trimWhitespace(_ value: String) -> String {
    var start = value.startIndex
    var end = value.endIndex

    while start < end, value[start].isWhitespace {
      start = value.index(after: start)
    }
    while start < end {
      let previous = value.index(before: end)
      guard value[previous].isWhitespace else { break }
      end = previous
    }
    return String(value[start..<end])
  }

  static func identifier(forMIMEType mimeType: String) -> String? {
    mimeTypes[mimeType]
  }

  static func identifier(forFilenameExtension filenameExtension: String) -> String? {
    filenameExtensions[filenameExtension]
  }

  static let definitions: [String: Definition] = [
    "public.item": Definition(),
    "public.content": Definition(parents: ["public.item"]),
    "public.composite-content": Definition(parents: ["public.content"]),
    "public.data": Definition(parents: ["public.item"], mimeType: "application/octet-stream"),
    "public.directory": Definition(parents: ["public.item"], filenameExtension: nil),

    "public.text": Definition(parents: ["public.data"], mimeType: "text/plain"),
    "public.plain-text": Definition(
      parents: ["public.text"], mimeType: "text/plain", filenameExtension: "txt",
      filenameAliases: ["text"]
    ),
    "public.utf8-plain-text": Definition(parents: ["public.plain-text"], mimeType: "text/plain", filenameExtension: "txt"),
    "public.html": Definition(
      parents: ["public.text"], mimeType: "text/html", filenameExtension: "html",
      filenameAliases: ["htm"]
    ),
    "public.xml": Definition(
      parents: ["public.text"], mimeType: "application/xml", filenameExtension: "xml",
      mimeAliases: ["text/xml"]
    ),
    "public.json": Definition(parents: ["public.text"], mimeType: "application/json", filenameExtension: "json"),
    "public.delimited-values-text": Definition(parents: ["public.text"], mimeType: nil, filenameExtension: nil),
    "public.tab-separated-values-text": Definition(parents: ["public.delimited-values-text"], mimeType: "text/tab-separated-values", filenameExtension: "tsv"),
    "public.rtf": Definition(parents: ["public.text"], mimeType: "text/rtf", filenameExtension: "rtf"),
    "public.comma-separated-values-text": Definition(parents: ["public.delimited-values-text"], mimeType: "text/csv", filenameExtension: "csv"),

    "public.url": Definition(parents: ["public.data"], mimeType: "text/url", filenameExtension: "url", mimeAliases: ["text/uri-list"]),
    "public.file-url": Definition(parents: ["public.url"], filenameExtension: "fileurl"),

    "public.image": Definition(parents: ["public.data"], mimeType: "image/*"),
    "public.jpeg": Definition(parents: ["public.image"], mimeType: "image/jpeg", filenameExtension: "jpeg", filenameAliases: ["jpg", "jpe"]),
    "public.png": Definition(parents: ["public.image"], mimeType: "image/png", filenameExtension: "png"),
    "public.heic": Definition(parents: ["public.image"], mimeType: "image/heic", filenameExtension: "heic", filenameAliases: ["heif"]),
    "org.webmproject.webp": Definition(parents: ["public.image"], mimeType: "image/webp", filenameExtension: "webp"),
    "com.compuserve.gif": Definition(parents: ["public.image"], mimeType: "image/gif", filenameExtension: "gif"),
    "public.svg-image": Definition(parents: ["public.image"], mimeType: "image/svg+xml", filenameExtension: "svg"),

    "public.audiovisual-content": Definition(parents: ["public.content"]),
    // A movie is a concrete video representation; retaining the
    // audiovisual-content parent also matches the broad UTI category used by
    // drag/drop and media filters.
    "public.movie": Definition(parents: ["public.video", "public.audiovisual-content"], mimeType: "video/quicktime", filenameExtension: "mov"),
    "public.video": Definition(parents: ["public.audiovisual-content"], mimeType: "video/*"),
    "public.mpeg-4": Definition(parents: ["public.video"], mimeType: "video/mp4", filenameExtension: "mp4"),
    "public.audio": Definition(parents: ["public.audiovisual-content"], mimeType: "audio/*"),

    "com.adobe.pdf": Definition(parents: ["public.data"], mimeType: "application/pdf", filenameExtension: "pdf"),
    "public.archive": Definition(parents: ["public.data"]),
    "public.zip-archive": Definition(parents: ["public.archive"], mimeType: "application/zip", filenameExtension: "zip"),
    "org.gnu.gnu-zip-archive": Definition(parents: ["public.archive"], mimeType: "application/gzip", filenameExtension: "gz", filenameAliases: ["gzip"]),
    "public.tar-archive": Definition(parents: ["public.archive"], mimeType: "application/x-tar", filenameExtension: "tar"),

    "com.apple.webarchive": Definition(parents: ["public.composite-content"], filenameExtension: "webarchive"),
    "public.source-code": Definition(parents: ["public.text"])
  ]

  // MIME aliases are intentionally private: browser-specific spellings
  // should not become part of the public UTType API.
  static let mimeTypes: [String: String] = [
    "application/octet-stream": "public.data",
    "text/plain": "public.plain-text",
    "text/*": "public.text",
    "text/html": "public.html",
    "application/xml": "public.xml",
    "text/xml": "public.xml",
    "application/json": "public.json",
    "text/url": "public.url",
    "text/uri-list": "public.url",
    "image/*": "public.image",
    "image/jpeg": "public.jpeg",
    "image/jpg": "public.jpeg",
    "image/png": "public.png",
    "image/heic": "public.heic",
    "image/heif": "public.heic",
    "image/gif": "com.compuserve.gif",
    "image/webp": "org.webmproject.webp",
    "image/svg+xml": "public.svg-image",
    "video/quicktime": "public.movie",
    "video/*": "public.video",
    "video/mp4": "public.mpeg-4",
    "video/webm": "public.video",
    "audio/*": "public.audio",
    "audio/mpeg": "public.audio",
    "audio/mp3": "public.audio",
    "audio/wav": "public.audio",
    "audio/x-wav": "public.audio",
    "application/pdf": "com.adobe.pdf",
    "application/x-archive": "public.archive",
    "application/zip": "public.zip-archive",
    "application/gzip": "org.gnu.gnu-zip-archive",
    "application/x-gzip": "org.gnu.gnu-zip-archive",
    "application/x-tar": "public.tar-archive",
    "application/x-7z-compressed": "public.archive",
    "application/x-rar-compressed": "public.archive",
    "application/vnd.rar": "public.archive"
  ]

  static let filenameExtensions: [String: String] = [
    "txt": "public.plain-text",
    "text": "public.plain-text",
    "html": "public.html",
    "htm": "public.html",
    "xml": "public.xml",
    "json": "public.json",
    "url": "public.url",
    "fileurl": "public.file-url",
    "jpeg": "public.jpeg",
    "jpg": "public.jpeg",
    "jpe": "public.jpeg",
    "png": "public.png",
    "heic": "public.heic",
    "heif": "public.heic",
    "webp": "org.webmproject.webp",
    "gif": "com.compuserve.gif",
    "svg": "public.svg-image",
    "mov": "public.movie",
    "mp4": "public.mpeg-4",
    "m4v": "public.video",
    "webm": "public.video",
    "avi": "public.video",
    "mkv": "public.video",
    "mp3": "public.audio",
    "mpeg": "public.audio",
    "wav": "public.audio",
    "wave": "public.audio",
    "m4a": "public.audio",
    "ogg": "public.audio",
    "oga": "public.audio",
    "flac": "public.audio",
    "pdf": "com.adobe.pdf",
    "zip": "public.zip-archive",
    "gz": "org.gnu.gnu-zip-archive",
    "gzip": "org.gnu.gnu-zip-archive",
    "tar": "public.tar-archive",
    "webarchive": "com.apple.webarchive"
  ]
}

#if !hasFeature(Embedded)
/// Archived as its identifier, as UniformTypeIdentifiers archives a type.
extension UTType: Codable {
  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(String.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(identifier)
  }
}
#endif
