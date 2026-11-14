/// Semantic identity shared by every scrolling surface.  The browser owns
/// physical offsets; this value is the stable owner used by Swift state,
/// BrowserIO restoration and the layout viewport record.
public struct _ScrollID: Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init<ID: Hashable>(_ value: ID) {
    rawValue = fiberKeyDescription(_FiberKey(value))
  }

  public init(rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
}

@_spi(Renderer) public struct _ScrollNode: Hashable, Sendable {
  public let id: _ScrollID
  public let axes: Axis.Set

  public init(id: _ScrollID, axes: Axis.Set) {
    self.id = id
    self.axes = axes
  }

  @MainActor public static func id(for context: _RenderContext, kind: String) -> _ScrollID {
    _ScrollID(rawValue: "\(kind):\(context._compactPathID)")
  }

  public func apply(to node: _RenderNode) {
    node.attributes["data-scroll-node"] = "true"
    node.attributes["data-scroll-id"] = id.rawValue
    node.attributes["data-scroll-axes"] = String(axes.rawValue)
    node.attributes["data-layout-kind"] = "scroll"
  }
}
