/// SwiftUI's key equivalent: the key of a keyboard shortcut or of a
/// `KeyPress`. Special keys use the same private-use/control characters as
/// SwiftUI so values compare equal to the ones application code spells.
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
  public var character: Character

  public init(_ character: Character) { self.character = character }
  public init(extendedGraphemeClusterLiteral value: Character) { self.character = value }

  public static let upArrow = KeyEquivalent("\u{F700}")
  public static let downArrow = KeyEquivalent("\u{F701}")
  public static let leftArrow = KeyEquivalent("\u{F702}")
  public static let rightArrow = KeyEquivalent("\u{F703}")
  public static let escape = KeyEquivalent("\u{1B}")
  public static let delete = KeyEquivalent("\u{8}")
  public static let deleteForward = KeyEquivalent("\u{7F}")
  public static let home = KeyEquivalent("\u{F729}")
  public static let end = KeyEquivalent("\u{F72B}")
  public static let pageUp = KeyEquivalent("\u{F72C}")
  public static let pageDown = KeyEquivalent("\u{F72D}")
  public static let clear = KeyEquivalent("\u{F739}")
  public static let tab = KeyEquivalent("\t")
  public static let space = KeyEquivalent(" ")
  public static let `return` = KeyEquivalent("\r")
}

/// Browser `KeyboardEvent.key` names for SwiftUI's special keys. The browser
/// host compares these tokens; printable keys use their lowercased character.
private let _webKeyNames: [(Character, String)] = [
  ("\u{F700}", "ArrowUp"), ("\u{F701}", "ArrowDown"), ("\u{F702}", "ArrowLeft"),
  ("\u{F703}", "ArrowRight"), ("\u{1B}", "Escape"), ("\u{8}", "Backspace"),
  ("\u{7F}", "Delete"), ("\u{F729}", "Home"), ("\u{F72B}", "End"),
  ("\u{F72C}", "PageUp"), ("\u{F72D}", "PageDown"), ("\u{F739}", "Clear"),
  ("\t", "Tab"), (" ", "Space"), ("\r", "Enter")
]

extension KeyEquivalent {
  /// Host token used by the browser keyboard adapters.
  @_spi(Renderer) public var _webKeyToken: String {
    for (character, name) in _webKeyNames where character == self.character { return name }
    return String(character).lowercased()
  }

  /// Decodes a browser `KeyboardEvent.key`. Modifier-only keys and unknown
  /// named keys do not produce a SwiftUI key equivalent.
  @_spi(Renderer) public init?(_webKey key: String) {
    if key == " " { self = .space; return }
    for (character, name) in _webKeyNames where name == key { self.init(character); return }
    if key == "NumpadEnter" { self = .return; return }
    var iterator = key.makeIterator()
    guard let first = iterator.next(), iterator.next() == nil else { return nil }
    self.init(first)
  }
}

/// Modifier keys, matching SwiftUI's `EventModifiers` option set.
public struct EventModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let capsLock = EventModifiers(rawValue: 1 << 0)
  public static let shift = EventModifiers(rawValue: 1 << 1)
  public static let control = EventModifiers(rawValue: 1 << 2)
  public static let option = EventModifiers(rawValue: 1 << 3)
  public static let command = EventModifiers(rawValue: 1 << 4)
  public static let numericPad = EventModifiers(rawValue: 1 << 5)
  public static let function = EventModifiers(rawValue: 1 << 6)
  public static let all: EventModifiers = [.capsLock, .shift, .control, .option, .command, .numericPad, .function]
}

extension EventModifiers {
  /// Stable comma-separated names consumed by the browser host.
  @_spi(Renderer) public var _webTokens: String {
    var names: [String] = []
    if contains(.command) { names.append("command") }
    if contains(.control) { names.append("control") }
    if contains(.option) { names.append("option") }
    if contains(.shift) { names.append("shift") }
    return names.joined(separator: ",")
  }
}
