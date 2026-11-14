import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
import SwiftUIWeb

/// `writeAttributes` assembles class, style and event attributes without copying the attribute dictionary or
/// joining intermediate strings. This is a differential test against the straightforward algorithm it replaced:
/// whatever the node holds, the bytes must be the same.
@MainActor
struct HTMLAttributeWritingTests {
  private struct Generator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      return state >> 33
    }
    mutating func pick<T>(_ values: [T]) -> T { values[Int(next() % UInt64(values.count))] }
    mutating func chance(_ percent: UInt64) -> Bool { next() % 100 < percent }
  }

  private static let names = ["id", "role", "aria-label", "data-x", "title", "tabindex", "z", "A", "data-a", "data-b", "class", "style"]
  private static let values = ["", "a", "two words", "<b>&\"'", "x:y;", "é"]
  private static let classes = ["row", "stack", "a b", "<c>", "é"]
  private static let styleKeys = ["width", "height", "color", "--custom-x", "margin-top", "A"]
  private static let events = ["click", "appear", "task", "submit", "geometry", "mouseenter", "web-navigation", "focus"]

  private func escape(_ text: String) -> String {
    var result = ""
    for character in text {
      switch character {
      case "&": result += "&amp;"
      case "<": result += "&lt;"
      case ">": result += "&gt;"
      case "\"": result += "&quot;"
      case "'": result += "&#39;"
      default: result.append(character)
      }
    }
    return result
  }

  /// The algorithm `writeAttributes` had before: copy the dictionary, join class and style, sort the keys.
  private func reference(_ node: _RenderNode, hitTransparent: Bool) -> String {
    var attrs = node.attributes
    let classes = hitTransparent ? node.classes + ["passthrough"] : node.classes
    if !classes.isEmpty { attrs["class"] = ([attrs["class"]].compactMap { $0 } + classes).joined(separator: " ") }
    if !node.styles.isEmpty {
      attrs["style"] = ([attrs["style"]].compactMap { $0 } + node.styles.keys.sorted().map { "\($0): \(node.styles[$0] ?? "");" }).joined(separator: " ")
    }
    for name in node.events.keys.sorted() {
      guard !["appear", "disappear", "task", "geometry", "geometryChange", "openURL", "presentation-dismiss", "web-navigation", "web-external-link"].contains(name),
            let event = node.events[name] else { continue }
      attrs["data-fiber-event-\(name)"] = event.name
    }
    return attrs.keys.sorted().map { " \($0)=\"\(escape(attrs[$0] ?? ""))\"" }.joined()
  }

  private func attributeText(of html: String) -> String {
    guard html.hasPrefix("<div"), let close = html.firstIndex(of: ">") else { return html }
    return String(html[html.index(html.startIndex, offsetBy: 4)..<close])
  }

  @Test func `Random nodes serialize exactly as the straightforward algorithm would`() {
    var generator = Generator(state: 0x5EED)
    var passthroughRounds = 0
    defer { #expect(passthroughRounds > 20, "the generator reaches the pass-through branch") }
    for round in 0..<600 {
      let node = _RenderNode.element("div")
      for name in Self.names where generator.chance(35) { node.attributes[name] = generator.pick(Self.values) }
      if generator.chance(50) { node.attributes["data-layout-kind"] = "aspect" }      // a layout kind: pass-through unless something paints or listens
      for name in Self.classes where generator.chance(30) { node.classes.append(name) }
      for key in Self.styleKeys where generator.chance(30) { node.styles[key] = generator.pick(Self.values) }
      for name in Self.events where generator.chance(30) { node.events[name] = _EventHandler(name: generator.pick(["x", "y<z", "submit"]), action: {}) }
      let html = node.htmlDescription
      let hitTransparent = node._isHitTransparent
      if hitTransparent { passthroughRounds += 1 }
      #expect(attributeText(of: html) == reference(node, hitTransparent: hitTransparent), "round \(round): \(html)")
    }
  }

  @Test func `A class attribute and a class list are joined in that order, and a style attribute before the table`() {
    let node = _RenderNode.element("div")
    node.attributes["class"] = "own"
    node.classes = ["a", "b"]
    node.attributes["style"] = "top: 1px;"
    node.styles = ["width": "2px", "color": "red"]
    #expect(attributeText(of: node.htmlDescription) == #" class="own a b" style="top: 1px; color: red; width: 2px;""#)
  }

  @Test func `An event with the name of an existing attribute replaces it`() {
    let node = _RenderNode.element("div")
    node.attributes["data-fiber-event-click"] = "stale"
    node.events["click"] = _EventHandler(name: "fresh", action: {})
    #expect(attributeText(of: node.htmlDescription) == #" data-fiber-event-click="fresh""#)
  }
}
