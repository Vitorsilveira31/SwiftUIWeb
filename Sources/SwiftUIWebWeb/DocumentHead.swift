@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// One `<meta>` or `<link>` element a screen asks the page's `<head>` to carry.
///
/// Build values with the static functions and hand them to ``SwiftUIWebCore/View/documentHead(_:)``.
/// Only these two tags can be expressed, and only attributes the browser host accepts reach the page.
public struct HeadElement: Hashable, Sendable {
  struct Attribute: Hashable, Sendable {
    let name: String
    let value: String
  }

  let tag: String
  let attributes: [Attribute]

  private static func element(_ tag: String, _ attributes: [(String, String?)]) -> HeadElement {
    var present: [Attribute] = []
    for (name, value) in attributes {
      if let value { present.append(Attribute(name: name, value: value)) }
    }
    return HeadElement(tag: tag, attributes: present)
  }

  /// The tab icon (`<link rel="icon">`). Use `media` for a variant that applies only to a color scheme,
  /// for example `"(prefers-color-scheme: dark)"`.
  public static func favicon(_ href: String, type: String? = nil, sizes: String? = nil, media: String? = nil) -> HeadElement {
    element("link", [("rel", "icon"), ("href", href), ("type", type), ("sizes", sizes), ("media", media)])
  }

  /// `<meta name="..." content="...">`, for example `description` or `robots`.
  public static func meta(name: String, content: String) -> HeadElement {
    element("meta", [("name", name), ("content", content)])
  }

  /// `<meta property="..." content="...">`, the form Open Graph uses (`og:title`, `og:image`).
  public static func meta(property: String, content: String) -> HeadElement {
    element("meta", [("property", property), ("content", content)])
  }

  /// The browser chrome color on mobile (`<meta name="theme-color">`), optionally for one color scheme.
  public static func themeColor(_ color: String, media: String? = nil) -> HeadElement {
    element("meta", [("name", "theme-color"), ("content", color), ("media", media)])
  }

  /// The preferred address of the page (`<link rel="canonical">`).
  public static func canonical(_ href: String) -> HeadElement {
    element("link", [("rel", "canonical"), ("href", href)])
  }
}

/// Collects the elements of a ``SwiftUIWebCore/View/documentHead(_:)`` block.
@resultBuilder
public enum HeadBuilder {
  public static func buildExpression(_ element: HeadElement) -> [HeadElement] { [element] }
  public static func buildExpression(_ elements: [HeadElement]) -> [HeadElement] { elements }
  public static func buildBlock(_ parts: [HeadElement]...) -> [HeadElement] {
    var all: [HeadElement] = []
    for part in parts { all.append(contentsOf: part) }
    return all
  }
  public static func buildOptional(_ part: [HeadElement]?) -> [HeadElement] { part ?? [] }
  public static func buildEither(first part: [HeadElement]) -> [HeadElement] { part }
  public static func buildEither(second part: [HeadElement]) -> [HeadElement] { part }
  public static func buildArray(_ parts: [[HeadElement]]) -> [HeadElement] {
    var all: [HeadElement] = []
    for part in parts { all.append(contentsOf: part) }
    return all
  }
}

/// Adds head elements to the page while the modified view is on screen.
public nonisolated struct DocumentHeadModifier: ViewModifier {
  let elements: [HeadElement]

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // A fragment or text root cannot carry an attribute, so it gets a wrapper that does not take part in layout.
    switch node.kind {
    case .fragment, .text:
      let original = node.clone()
      node.kind = .element("div")
      node.text = nil
      node.children = [original]
      node.styles["display"] = "contents"
    default:
      break
    }
    node.attributes["data-document-head"] = _documentHeadJSON(elements)
  }
}

public extension View {
  /// Adds `<meta>` and `<link>` elements to the page's `<head>` while this view is visible.
  ///
  /// This is web-only; SwiftUI has no equivalent. An app that also builds for Apple platforms guards it with
  /// `#if canImport(SwiftUIWebWeb)`. Like `navigationTitle`, the innermost visible screen wins: when two visible
  /// views declare the same element (the same icon, or the same `name` and `media`), the inner one applies.
  /// An element from the page's static `head.html` is replaced while a screen overrides it and comes back
  /// when that screen leaves.
  ///
  /// ```swift
  /// OrdersScreen()
  ///   .documentHead {
  ///     .favicon("/icons/alert.png")
  ///     .meta(name: "robots", content: "noindex")
  ///   }
  /// ```
  nonisolated func documentHead(@HeadBuilder _ content: () -> [HeadElement]) -> ModifiedContent<Self, DocumentHeadModifier> {
    modifier(DocumentHeadModifier(elements: content()))
  }
}

/// `[{"tag":"meta","attrs":{"name":"robots","content":"noindex"}}, ...]`, read by the browser host.
func _documentHeadJSON(_ elements: [HeadElement]) -> String {
  var json = "["
  var firstElement = true
  for element in elements {
    if !firstElement { json += "," }
    firstElement = false
    json += "{\"tag\":"
    _appendJSONString(element.tag, to: &json)
    json += ",\"attrs\":{"
    var firstAttribute = true
    for attribute in element.attributes {
      if !firstAttribute { json += "," }
      firstAttribute = false
      _appendJSONString(attribute.name, to: &json)
      json += ":"
      _appendJSONString(attribute.value, to: &json)
    }
    json += "}}"
  }
  json += "]"
  return json
}

private func _appendJSONString(_ text: String, to json: inout String) {
  let hex: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
  json += "\""
  for scalar in text.unicodeScalars {
    switch scalar.value {
    case 0x22: json += "\\\""
    case 0x5C: json += "\\\\"
    case 0..<0x20:
      json += "\\u00"
      json.append(hex[Int(scalar.value >> 4)])
      json.append(hex[Int(scalar.value & 0xF)])
    default:
      json.unicodeScalars.append(scalar)
    }
  }
  json += "\""
}
