@_spi(Renderer) import SwiftUIWebTransferable
/// Guards for markup that comes from caller-supplied strings: URL attributes,
/// element names, and attribute names. Escaping keeps a value inside its
/// attribute; these checks keep the value or name from meaning something
/// executable once it is there.

/// URL schemes a link or resource attribute may use. A value without a scheme
/// (a relative path, a query, or a fragment) is always allowed.
private let _safeURLSchemes: [String] = ["http", "https", "mailto", "tel", "sms"]

/// The lowercased scheme of `value` as a browser reads it, or `nil` for a relative reference (no scheme before the
/// first `/`, `?` or `#`). Browsers drop ASCII tab and newline characters and leading control characters or spaces
/// before reading a scheme, so `java\tscript:` is read the same way here.
package func _urlScheme(_ value: String) -> String? {
  var scheme = ""
  var started = false
  for byte in value.utf8 {
    if byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
    if !started && byte <= 0x20 { continue }
    started = true
    switch byte {
    case UInt8(ascii: ":"):
      return scheme
    case UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#"):
      return nil
    case UInt8(ascii: "A")...UInt8(ascii: "Z"):
      scheme.unicodeScalars.append(Unicode.Scalar(byte + 0x20))
    default:
      scheme.unicodeScalars.append(Unicode.Scalar(byte))
    }
  }
  return nil
}

/// Returns `value` when its scheme is safe for `href`/`src`, otherwise `nil`.
func _safeURLAttribute(_ value: String) -> String? {
  guard let scheme = _urlScheme(value) else { return value }
  return _safeURLSchemes.contains(scheme) ? value : nil
}

/// Element names `HTMLElement` refuses because they execute or embed content, load a resource of their own (`link`), or
/// animate another element's attributes: SVG's `set` and `animate` can turn an `href` into `javascript:` past the URL check.
private let _blockedElementNames: [String] = [
  "script", "iframe", "object", "embed", "frame", "frameset", "base", "meta", "link",
  "set", "animate", "animatemotion", "animatetransform", "style",
]

/// Attributes whose value is a URL, checked with ``_safeURLAttribute(_:)``.
private let _urlAttributeNames: [String] = ["href", "src", "action", "formaction", "xlink:href", "poster", "data"]

/// `true` for an ASCII element name such as `section` or `my-widget` that is
/// not in the blocked list.
func _isSafeElementName(_ name: String) -> Bool {
  guard let first = name.utf8.first, _isASCIILetter(first) else { return false }
  for byte in name.utf8 where !(_isASCIILetter(byte) || _isASCIIDigit(byte) || byte == UInt8(ascii: "-")) {
    return false
  }
  return !_blockedElementNames.contains(_asciiLowercased(name))
}

/// `true` for an attribute name such as `aria-label` or `data-id`; event
/// handler attributes (`on…`) and names with markup characters are refused.
func _isSafeAttributeName(_ name: String) -> Bool {
  guard let first = name.utf8.first, _isASCIILetter(first) || first == UInt8(ascii: "_") else { return false }
  for byte in name.utf8 {
    let allowed = _isASCIILetter(byte) || _isASCIIDigit(byte)
      || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ":") || byte == UInt8(ascii: ".")
    if !allowed { return false }
  }
  return !_asciiLowercased(name).hasPrefix("on")
}

/// Keeps the attributes whose names are safe, and drops URL attributes whose
/// scheme is not.
func _safeAttributes(_ attributes: [String: String]) -> _NodeValues {
  var result: _NodeValues = .init()
  for (name, value) in attributes {
    if let safe = _safeAttributeValue(name: name, value: value) { result[name] = safe }
  }
  return result
}

/// The value to write for one attribute, or `nil` when the name is unsafe or the name takes a URL whose scheme is not.
func _safeAttributeValue(name: String, value: String) -> String? {
  guard _isSafeAttributeName(name) else { return nil }
  let lowered = _asciiLowercased(name)
  guard _urlAttributeNames.contains(lowered) else { return value }
  // An image or video source may also be a data: or blob: URL, as an Image's may: it loads pixels, it does not navigate.
  if lowered == "src" || lowered == "poster", let scheme = _urlScheme(value), scheme == "data" || scheme == "blob" { return value }
  return _safeURLAttribute(value)
}

/// The value a mounted element (`WebElementHandle.setAttribute`, a media source) may take for `name`, or nil. The
/// escape hatch keeps every ordinary attribute, but never an event handler (`on…`), `srcdoc` (a document of markup), or
/// a URL attribute whose scheme could run script; `blob:` and `data:` stay allowed for media and images.
package func _safeMountedAttributeValue(name: String, value: String) -> String? {
  guard _isSafeAttributeName(name), _asciiLowercased(name) != "srcdoc" else { return nil }
  guard _urlAttributeNames.contains(_asciiLowercased(name)) else { return value }
  return _isSafeMountedURL(value) ? value : nil
}

/// A URL a mounted element may load: relative, or one of the link schemes, `blob:` or `data:`.
package func _isSafeMountedURL(_ value: String) -> Bool {
  guard let scheme = _urlScheme(value) else { return true }
  return _safeURLSchemes.contains(scheme) || scheme == "blob" || scheme == "data"
}

private func _isASCIILetter(_ byte: UInt8) -> Bool {
  (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
}

private func _isASCIIDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }

private func _asciiLowercased(_ value: String) -> String {
  var result = ""
  for byte in value.utf8 {
    let lowered = (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 0x20 : byte
    result.unicodeScalars.append(Unicode.Scalar(lowered))
  }
  return result
}
