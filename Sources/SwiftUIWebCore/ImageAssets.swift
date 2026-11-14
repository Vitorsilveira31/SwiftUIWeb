/// Asset-catalog images on the web. SwiftUI resolves `Image("Name")` from
/// the app's asset catalog; the browser build has no bundle, so the host
/// installs the table that `Tools/compile-assets.mjs` generated from the
/// package's `*.imageset`s (name → bundle-relative file) before the first
/// render, and `Image` renders that file. A name without an entry is used as
/// a file path of the app's own site (`media/cover.jpg`, a `data:` or `blob:`
/// URL); a remote URL is not, as SwiftUI's `Image("name")` never loads one, so
/// a name built from server data cannot make the page fetch from any host.
@_spi(Renderer) public enum _ImageAssets {
  @MainActor private static var table: [String: String] = [:]

  /// Replaces the table; nil clears it (tests, session disposal).
  @MainActor public static func install(_ images: [String: String]?) {
    table = images ?? [:]
  }

  /// Parses the generated `Name=path;Name=path` manifest text.
  @MainActor public static func install(manifest: String) {
    var images: [String: String] = [:]
    for entry in manifest.split(separator: ";") {
      guard let separator = entry.firstIndex(of: "=") else { continue }
      let name = String(entry[..<separator])
      let path = String(entry[entry.index(after: separator)...])
      if !name.isEmpty, !path.isEmpty { images[name] = path }
    }
    table = images
  }

  @MainActor public static func resolve(_ name: String) -> String? { table[name] }

  /// Inside the framework's own strings (an image interpolated into `Text`, a canvas image), a source that may be remote
  /// (`Image(_:alt:)`, an `AsyncImage` load) carries this prefix. Applications cannot write it: the image markers it
  /// travels in are removed from interpolated strings.
  package static let remoteSourceMark = "\u{1}"

  /// Escapes an unprivileged name that itself starts with one of the marks, so a name from data cannot claim the
  /// remote permission.
  package static let plainSourceMark = "\u{2}"

  /// `name` with the remote mark when `allowsRemote`. Without it, a name that starts with a mark is escaped with
  /// `plainSourceMark`, so the mark is only ever the framework's.
  package static func marked(_ name: String, allowsRemote: Bool) -> String {
    if allowsRemote { return remoteSourceMark + name }
    return name.hasPrefix(remoteSourceMark) || name.hasPrefix(plainSourceMark) ? plainSourceMark + name : name
  }

  /// The source a marked name stands for (see `marked(_:allowsRemote:)`).
  @MainActor package static func source(forMarked name: String) -> String? {
    if name.hasPrefix(remoteSourceMark) { return source(for: String(name.dropFirst()), allowsRemote: true) }
    if name.hasPrefix(plainSourceMark) { return source(for: String(name.dropFirst())) }
    return source(for: name)
  }

  /// What an image named `name` loads: its asset file, else the name itself when it is a path of the app's site (or a
  /// `data:`/`blob:` URL), or any URL when `allowsRemote` (the framework's own `Image(_:alt:)`); nil otherwise.
  @MainActor public static func source(for name: String, allowsRemote: Bool = false) -> String? {
    if let asset = table[name] { return asset }
    if allowsRemote || isLocalPath(name) { return name }
    return nil
  }

  /// A relative or root-relative path, with no scheme and no other host (`//host` or a backslash), or a `data:` or
  /// `blob:` URL.
  public static func isLocalPath(_ name: String) -> Bool {
    // Classified as the browser reads the URL: it drops leading spaces and control characters, and every tab and line
    // break, so " //host/p" or "/\t/host/p" names another host.
    var normalized = String.UnicodeScalarView()
    var leading = true
    for scalar in name.unicodeScalars {
      if leading && scalar.value <= 0x20 { continue }
      leading = false
      if scalar == "\t" || scalar == "\n" || scalar == "\r" { continue }
      normalized.append(scalar)
    }
    let name = String(normalized)
    if name.hasPrefix("data:") || name.hasPrefix("blob:") { return true }
    if name.isEmpty || name.hasPrefix("//") || name.contains("\\") { return false }
    // A ":" before the first "/", "?" or "#" starts a scheme (`https:`, `javascript:`).
    for character in name {
      if character == "/" || character == "?" || character == "#" { return true }
      if character == ":" { return false }
    }
    return true
  }

  @MainActor public static var isEmpty: Bool { table.isEmpty }
}
