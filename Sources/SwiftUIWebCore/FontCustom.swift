/// SwiftUI's custom-font factories.
///
/// Browser hosts resolve the family through CSS. The emitted family list is
///
///     var(--asset-font-<slug>, "<Name>", system-ui, -apple-system, …, sans-serif)
///
/// so an application stylesheet can supply a better fallback stack for one
/// family (for example a serif stack for a serif display face) without Swift
/// source changes: `--asset-font-newsreader: "Newsreader", Georgia, serif;`.
/// The web font itself is loaded by the application's document head (`Resources/head.html`, see
/// `Documentation/BROWSER_APP_SHELL.md`). Layout re-measures text
/// when `document.fonts` finishes loading, so intrinsic sizes follow the real
/// face instead of the fallback.
extension Font {
  /// SwiftUI's semantic text styles. Browsers have no Dynamic Type setting,
  /// so `custom(_:size:relativeTo:)` keeps the requested point size; the
  /// style is retained for source compatibility with Apple platforms.
  public enum TextStyle: Hashable, Sendable {
    case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2
  
    /// The CSS spelling of each case; SwiftUI does not expose a raw value.
    var rawValue: String {
      switch self {
      case .largeTitle: "largeTitle"
      case .title: "title"
      case .title2: "title2"
      case .title3: "title3"
      case .headline: "headline"
      case .subheadline: "subheadline"
      case .body: "body"
      case .callout: "callout"
      case .footnote: "footnote"
      case .caption: "caption"
      case .caption2: "caption2"
      }
    }
  }

  /// A custom font of the given family and size.
  public static func custom(_ name: String, size: CGFloat) -> Font {
    Font(cssStyles: _customFontStyles(name, size: Double(size)))
  }

  /// A custom font that would scale relative to `textStyle` on platforms with
  /// Dynamic Type. The browser host renders the requested size.
  public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
    var styles = _customFontStyles(name, size: Double(size))
    styles["--font-text-style"] = textStyle.rawValue
    return Font(cssStyles: styles)
  }

  /// A custom font with a fixed size that never scales.
  public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
    Font(cssStyles: _customFontStyles(name, size: Double(fixedSize)))
  }
}

private let _customFontFallbackStack =
  "system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, sans-serif"

private func _customFontStyles(_ name: String, size: Double) -> _NodeValues {
  let family = _cssFontFamilyName(name)
  let slug = _cssFontFamilySlug(family)
  let stack = family.isEmpty ? _customFontFallbackStack : "\"\(family)\", \(_customFontFallbackStack)"
  let resolved = slug.isEmpty ? stack : "var(--asset-font-\(slug), \(stack))"
  let points = size.isFinite && size > 0 ? size : 17
  let pixels = Int64(exactly: points).map { String($0) } ?? String(points)
  // Match `Font.system(size:)`: a SwiftUI font owns its own line box instead
  // of inheriting the document's 1.5 leading.
  return ["font-family": resolved, "font-size": "\(pixels)px", "line-height": "normal"]
}

/// Removes characters that could terminate the quoted CSS family token.
private func _cssFontFamilyName(_ name: String) -> String {
  var result = ""
  for scalar in name.unicodeScalars {
    switch scalar {
    case "\"", "\\", ";", "{", "}", "<", ">", "\n", "\r", "\t": continue
    default:
      // Every other control character (U+000C, U+007F, ...) is dropped too: a raw one is not valid in a CSS string.
      if scalar.value < 0x20 || scalar.value == 0x7F { continue }
      result.unicodeScalars.append(scalar)
    }
  }
  return result
}

/// ASCII-only lowercase slug. Embedded Swift keeps Unicode case tables out of
/// the binary, so non-ASCII characters simply become separators.
private func _cssFontFamilySlug(_ name: String) -> String {
  var bytes: [UInt8] = []
  var pendingSeparator = false
  for byte in name.utf8 {
    let lowered: UInt8?
    switch byte {
    case 65...90: lowered = byte + 32
    case 97...122, 48...57: lowered = byte
    default: lowered = nil
    }
    if let lowered {
      if pendingSeparator && !bytes.isEmpty { bytes.append(45) }
      pendingSeparator = false
      bytes.append(lowered)
    } else {
      pendingSeparator = true
    }
  }
  return String(decoding: bytes, as: UTF8.self)
}
