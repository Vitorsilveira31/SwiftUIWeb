/// Minimal, internal Embedded Swift compatibility slice.
///
/// This module deliberately contains no Foundation, Observation, reflection,
/// `String` formatting, type erasure, dynamic casts, weak references, Codable,
/// or browser/JavaScript dependencies. It is a measurement and compatibility
/// probe, not a second application programming model. The normal SwiftUI API
/// continues to live in SwiftUIWebCore and is not conditionally replaced by
/// these types.

public struct EmbeddedCoreNode {
  public let kind: UInt8
  public let value: Int32
  public let firstChild: Int8
  public let childCount: UInt8

  public init(kind: UInt8 = 0, value: Int32 = 0, firstChild: Int8 = -1, childCount: UInt8 = 0) {
    self.kind = kind
    self.value = value
    self.firstChild = firstChild
    self.childCount = childCount
  }
}

/// A fixed-capacity contiguous arena keeps the Embedded probe free of dynamic
/// allocation and dictionary/set metadata. The production renderer can use a
/// larger arena/free-list; this intentionally proves the smallest viable
/// structural representation first.
public struct EmbeddedCoreArena {
  private let empty = EmbeddedCoreNode()
  private var slot0: EmbeddedCoreNode
  private var slot1: EmbeddedCoreNode
  private var slot2: EmbeddedCoreNode
  private var slot3: EmbeddedCoreNode
  private var slot4: EmbeddedCoreNode
  private var slot5: EmbeddedCoreNode
  private var slot6: EmbeddedCoreNode
  private var slot7: EmbeddedCoreNode
  public private(set) var count: UInt8 = 0

  public init() {
    slot0 = empty; slot1 = empty; slot2 = empty; slot3 = empty
    slot4 = empty; slot5 = empty; slot6 = empty; slot7 = empty
  }

  @discardableResult
  public mutating func append(_ node: EmbeddedCoreNode) -> Int8 {
    let handle = Int8(count)
    switch count {
    case 0: slot0 = node
    case 1: slot1 = node
    case 2: slot2 = node
    case 3: slot3 = node
    case 4: slot4 = node
    case 5: slot5 = node
    case 6: slot6 = node
    case 7: slot7 = node
    default: return -1
    }
    count &+= 1
    return handle
  }

  public func node(at handle: Int8) -> EmbeddedCoreNode {
    switch handle {
    case 0: return slot0
    case 1: return slot1
    case 2: return slot2
    case 3: return slot3
    case 4: return slot4
    case 5: return slot5
    case 6: return slot6
    case 7: return slot7
    default: return empty
    }
  }
}

/// A value-only state cell. It is intentionally concrete and stack-friendly;
/// the full framework's `@State`/Binding/Observation machinery remains in Core.
public struct EmbeddedCoreState {
  public var value: Int32

  public init(_ value: Int32) {
    self.value = value
  }
}

public enum EmbeddedCoreRenderer {
  /// `kind == 1` is a text leaf and its value is a compact application string
  /// table ID. `kind == 2` is a one-child container.
  public static func renderCounter(_ state: EmbeddedCoreState, into arena: inout EmbeddedCoreArena) -> Int8 {
    let text = arena.append(EmbeddedCoreNode(kind: 1, value: state.value))
    return arena.append(EmbeddedCoreNode(kind: 2, firstChild: text, childCount: 1))
  }
}

/// Exported only for the direct Embedded artifact smoke probe. There is no
/// public SwiftUIWeb API dependency on this symbol.
@_cdecl("embedded_core_start")
public func swiftuiwebEmbeddedCoreStart(_ value: Int32) -> Int32 {
  var state = EmbeddedCoreState(value)
  var arena = EmbeddedCoreArena()
  let root = EmbeddedCoreRenderer.renderCounter(state, into: &arena)
  state.value &+= 1
  _ = EmbeddedCoreRenderer.renderCounter(state, into: &arena)
  return Int32(arena.count) + Int32(arena.node(at: root).value)
}
