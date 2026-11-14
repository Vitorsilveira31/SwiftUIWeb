@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

/// The way a media player without a view reaches the page.
///
/// AVFoundation plays audio, and video without a layer, with no view on screen. A browser plays through a media element,
/// and the element is the page's, so the page's media host owns one for every player that has an item and no mounted
/// `VideoPlayer`. This is the small, view-less channel to it: each publication carries the players' wishes as one attribute
/// of the app root (`data-headless-media-wishes`, JSON), and the elements' reports come back through one reserved event route.
/// The wishes are the attributes a `VideoPlayer` would render, so the host applies them with the code it has for a mounted
/// element; the page decides, element by element, whether a view or the host holds a player.
@_spi(WebMount)
@MainActor public enum _HeadlessMedia {
  /// Set by the browser runtime when it can carry the channel (Embedded browser builds); players register only then.
  public static var isAvailable = false
  /// The wishes of every registered player, as a JSON array: `{"id","kind","attrs":{...}}`.
  public static var wishes: () -> String = { "[]" }
  /// A report from an element: the player's media id, the report's kind (`media-report` or `media-tracks-report`) and its payload.
  public static var receive: (String, String, String) -> Void = { _, _, _ in }
  /// Asks for a publication, so a changed wish reaches the page. Installed by the runtime.
  package static var requestPublish: () -> Void = {}
  public static func invalidate() { if isAvailable { requestPublish() } }

  /// The event node the reserved route delivers reports to. It is not in the view tree. Its events carry
  /// "<media id>|<payload>".
  package static let eventToken: UInt32 = 0xFFFF_FFF0
  package static let node: _RenderNode = {
    let node = _RenderNode.element("div")
    for kind in ["media-report", "media-tracks-report"] {
      node.events[kind + "-headless"] = _EventHandler(name: kind + "-headless", action: { value in
        guard let bar = value.firstIndex(of: "|") else { return }
        _HeadlessMedia.receive(String(value[..<bar]), kind, String(value[value.index(after: bar)...]))
      })
    }
    return node
  }()
}
