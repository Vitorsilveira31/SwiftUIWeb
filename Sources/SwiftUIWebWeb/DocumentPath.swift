@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The address the page shows while the modified view is on screen, built from path segments.
public nonisolated struct DocumentPathModifier: ViewModifier {
  let path: String

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
    node.attributes["data-url-path"] = path
  }
}

public extension View {
  /// Gives the page the address `/a/b` while this view is visible, so a link to that address, a reload and a shared URL
  /// come back to this screen.
  ///
  /// This is web-only; SwiftUI has no equivalent. An app that also builds for Apple platforms guards it with
  /// `#if canImport(SwiftUIWebWeb)`. Like `navigationTitle` and `documentHead`, the innermost visible screen wins: the view
  /// of the selected tab, or the destination a `NavigationStack` shows. A path that changes while the view stays on screen
  /// replaces the address in the browser's history, without adding an entry.
  ///
  /// The segments are joined with `/` and percent-escaped, and empty segments are dropped, so they can be built from
  /// state. Opening an address (a deep link, a reload) reaches the app through `onOpenURL`: the app reads the path there
  /// and puts its state where the path says, which is what makes the two directions agree.
  ///
  /// ```swift
  /// ComponentsScreen()
  ///   .tabItem { Text("Components") }
  ///   .tag(Page.components)
  ///   #if canImport(SwiftUIWebWeb)
  ///   .path("en", "components", selectedComponent)   // /en/components/slider
  ///   #endif
  /// ```
  nonisolated func path(_ segments: String...) -> some View {
    _modified(DocumentPathModifier(path: _documentPath(segments)))
  }

  /// The same, for segments held in an array.
  nonisolated func path(_ segments: [String]) -> some View {
    _modified(DocumentPathModifier(path: _documentPath(segments)))
  }
}

/// The segments as the path a page address holds, without the leading `/`: `["pt", "components", "Stack View"]` is
/// `pt/components/Stack%20View`. Only letters, digits and `-._~` are kept as they are.
package func _documentPath(_ segments: [String]) -> String {
  var parts: [String] = []
  for segment in segments {
    var part = ""
    for byte in segment.utf8 {
      let unreserved = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
        || byte == 45 || byte == 46 || byte == 95 || byte == 126
      if unreserved {
        part.append(Character(UnicodeScalar(byte)))
      } else if byte != 47 {
        let hex = String(byte, radix: 16, uppercase: true)
        part += "%" + (byte < 16 ? "0" : "") + hex
      }
    }
    // A "." or ".." segment would move the address up or stay in place, and the URL parser reads "%2E" as a dot too, so
    // such a segment is left out, like an empty one.
    if !part.isEmpty, part != ".", part != ".." { parts.append(part) }
  }
  return parts.joined(separator: "/")
}
