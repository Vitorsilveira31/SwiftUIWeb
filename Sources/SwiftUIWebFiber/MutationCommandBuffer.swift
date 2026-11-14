import SwiftUIWebCore

// Native-only: the Embedded browser has no consumer for the command stream.
#if !hasFeature(Embedded)

/// Compact, renderer-internal DOM command opcodes.
///
/// The browser adapter transports these records as four UInt32 words. Keeping
/// the wire representation numeric makes the Swift/WASM boundary independent
/// of the public SwiftUI API and avoids allocating an object/array for every
/// DOM mutation. This type is SPI-only: applications should never need to
/// construct or inspect a browser command.
@_spi(Renderer) public enum _DOMMutationOpcode: UInt32, Sendable {
  case create = 1
  case insert = 2
  case remove = 3
  case move = 4
  case setText = 5
  case setProperty = 6
  case setAttribute = 7
  case removeAttribute = 8
  case setStyle = 9
  case addEvent = 10
  case removeEvent = 11
}

@_spi(Renderer) public enum _DOMPropertyID: UInt32, Sendable {
  case value = 1
  case checked = 2
  case selected = 3
  case disabled = 4
}

/// Stable identifiers for the small, high-frequency vocabulary emitted by the
/// browser renderer. These IDs are part of the private SwiftUI/browser
/// protocol, not the SwiftUI-facing API. The table lets a command refer to a
/// framework name without appending another Swift `String` to the per-commit
/// bridge payload. Its JavaScript decoder (`dom-batch.js`) was
/// removed: the Embedded browser host patches the DOM from the published HTML
/// and no shipped host consumes this vocabulary, so a host that adopts it must
/// bring its own decoder.
///
/// Keep this table deliberately small. Arbitrary application strings (text,
/// URLs, user attributes, analytics payloads, and so on) remain dynamically
/// interned only for the duration of a commit; making those global would cost
/// more memory than it saves.
@_spi(Renderer) public enum _DOMStaticStringID: UInt32, Sendable {
  case tagDiv = 1
  case tagButton = 2
  case tagInput = 3
  case tagSelect = 4
  case tagOption = 5
  case tagTextarea = 6
  case tagImg = 7
  case tagAnchor = 8
  case tagSpan = 9

  case attributeClass = 10
  case attributeStyle = 11
  case attributeValue = 12
  case attributeChecked = 13
  case attributeSelected = 14
  case attributeDisabled = 15
  case attributeRole = 16
  case attributeID = 17
  case attributeTabIndex = 18

  case ariaLabel = 19
  case ariaHidden = 20
  case ariaDisabled = 21
  case ariaExpanded = 22
  case ariaControls = 23

  case styleDisplay = 24
  case styleFlex = 25
  case styleBlock = 26
  case styleNone = 27
  case styleWidth = 28
  case styleHeight = 29
  case styleColor = 30
  case styleBackgroundColor = 31

  case eventClick = 32
  case eventInput = 33
  case eventChange = 34
  case eventSubmit = 35
  case eventFocus = 36
  case eventBlur = 37
  case eventKeydown = 38
  case eventScroll = 39

  case markerEnter = 40
  case markerLazyCell = 41
  case markerFiberID = 42

  public static let count = 42

  /// The token bit distinguishes a static vocabulary ID from an index into
  /// the dynamic per-commit string table. String-table indices are small
  /// non-negative integers, so the high bit is available without changing the
  /// four-word command layout.
  public var token: UInt32 { 0x8000_0000 | rawValue }

  /// Exact matching is intentional: renderer-produced names are canonical
  /// lower-case HTML/CSS/event spellings. A lazily-created immutable table is
  /// faster than a long String switch in the browser hot path while retaining
  /// the dynamic fallback for custom names.
  private static let lookupTable: [String: Self] = [
    "div": .tagDiv, "button": .tagButton, "input": .tagInput,
    "select": .tagSelect, "option": .tagOption, "textarea": .tagTextarea,
    "img": .tagImg, "a": .tagAnchor, "span": .tagSpan,
    "class": .attributeClass, "style": .attributeStyle,
    "value": .attributeValue, "checked": .attributeChecked,
    "selected": .attributeSelected, "disabled": .attributeDisabled,
    "role": .attributeRole, "id": .attributeID, "tabindex": .attributeTabIndex,
    "aria-label": .ariaLabel, "aria-hidden": .ariaHidden,
    "aria-disabled": .ariaDisabled, "aria-expanded": .ariaExpanded,
    "aria-controls": .ariaControls,
    "display": .styleDisplay, "flex": .styleFlex, "block": .styleBlock,
    "none": .styleNone, "width": .styleWidth, "height": .styleHeight,
    "color": .styleColor, "background-color": .styleBackgroundColor,
    "click": .eventClick, "change": .eventChange, "submit": .eventSubmit,
    "focus": .eventFocus, "blur": .eventBlur, "keydown": .eventKeydown,
    "scroll": .eventScroll,
    "data-enter-animation": .markerEnter,
    "data-lazy-cell": .markerLazyCell,
    "data-fiber-id": .markerFiberID
  ]

  public static func lookup(_ value: String) -> Self? { lookupTable[value] }
}

/// Four-word command record used by the browser batch applier.
@_spi(Renderer) public struct _DOMMutationCommand: Equatable, Sendable {
  public let opcode: _DOMMutationOpcode
  public let a: UInt32
  public let b: UInt32
  public let c: UInt32

  public init(opcode: _DOMMutationOpcode, a: UInt32 = 0, b: UInt32 = 0, c: UInt32 = 0) {
    self.opcode = opcode
    self.a = a
    self.b = b
    self.c = c
  }

  public var words: [UInt32] { [opcode.rawValue, a, b, c] }
}

/// A compact string-interned command buffer. The browser receives one typed
/// command array and one string table for a commit, rather than one bridge
/// call per DOM operation. Node handles are deliberately kept by the browser
/// adapter because they contain JavaScript object references and are not part
/// of the backend-neutral Fiber layer.
@_spi(Renderer) public struct _DOMMutationCommandBuffer: Sendable {
  public static let noHandle: UInt32 = .max

  public private(set) var words: [UInt32] = []
  public private(set) var strings: [String] = []

  private var stringIDs: [String: UInt32] = [:]
  public private(set) var dynamicInternHits: Int = 0
  public private(set) var staticInternHits: Int = 0

  public init() {}

  public var commandCount: Int { words.count / 4 }
  public var wordCount: Int { words.count }
  public var encodedByteCount: Int { wordCount * MemoryLayout<UInt32>.size }

  @discardableResult
  public mutating func intern(_ value: String) -> UInt32 {
    if let id = stringIDs[value] {
      dynamicInternHits += 1
      return id
    }
    let id = UInt32(strings.count)
    strings.append(value)
    stringIDs[value] = id
    return id
  }

  /// Intern a known renderer vocabulary item as a high-bit token. The token
  /// is resolved by the browser helper's static table, so no Swift string is
  /// copied into this commit's bridge payload. This overload is SPI-only and
  /// cannot surface a browser concept through SwiftUI APIs.
  @discardableResult
  public mutating func intern(_ value: _DOMStaticStringID) -> UInt32 {
    staticInternHits += 1
    return value.token
  }

  /// Canonicalize renderer-produced names while retaining the dynamic path for
  /// custom application attributes, CSS properties, event names and values.
  @discardableResult
  public mutating func internFramework(_ value: String) -> UInt32 {
    if let staticValue = _DOMStaticStringID.lookup(value) {
      return intern(staticValue)
    }
    return intern(value)
  }

  public mutating func append(_ command: _DOMMutationCommand) {
    words.append(command.opcode.rawValue)
    words.append(command.a)
    words.append(command.b)
    words.append(command.c)
  }

  public mutating func append(_ opcode: _DOMMutationOpcode, a: UInt32 = 0, b: UInt32 = 0, c: UInt32 = 0) {
    append(_DOMMutationCommand(opcode: opcode, a: a, b: b, c: c))
  }
}
#endif
