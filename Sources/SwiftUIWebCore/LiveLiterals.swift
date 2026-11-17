// Literals the development loop can replace in a running page (the lowerer's `live-literals` pass writes the
// calls; nothing calls these in a build without it, so they are not in a release module).

/// A type a replaced string literal can be made of. A static function and not an initializer: an initializer on `Float` or
/// `String` would make an application's `values.map(Float.init)` ambiguous.
public protocol _LiveStringLiteral { static func _liveLiteral(_ value: String) -> Self }
/// A type a replaced number literal can be made of, from the number as it is written: an integer type reads it exactly
/// (a `Double` in between would round an `Int64` above 2^53), and a value the type cannot hold leaves the literal as it was.
public protocol _LiveNumberLiteral { static func _liveLiteral(number text: String) -> Self? }

extension String: _LiveStringLiteral { public static func _liveLiteral(_ value: String) -> Self { value } }
extension Substring: _LiveStringLiteral { public static func _liveLiteral(_ value: String) -> Self { Substring(value) } }
extension LocalizedStringKey: _LiveStringLiteral { public static func _liveLiteral(_ value: String) -> Self { Self(value) } }

// A one-character literal may be a `Character` or a key equivalent; a longer replacement gives them its first character.
extension Character: _LiveStringLiteral { public static func _liveLiteral(_ value: String) -> Self { value.first ?? " " } }
extension KeyEquivalent: _LiveStringLiteral { public static func _liveLiteral(_ value: String) -> Self { Self(value.first ?? " ") } }

extension Double: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension Float: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension Int: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension Int64: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension Int32: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension Int16: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension Int8: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension UInt: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension UInt64: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension UInt32: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension UInt16: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }
extension UInt8: _LiveNumberLiteral { public static func _liveLiteral(number text: String) -> Self? { Self(text) } }

public enum _LiveLiterals {
  enum Value {
    case string(String)
    case number(String)
    case bool(Bool)
  }

  nonisolated(unsafe) static var table: [UInt64: Value] = .init()
  /// The literals the page ran whose type has no live form (the fallback `_live`): a replacement for one changes nothing.
  nonisolated(unsafe) static var unsupported: Set<UInt64> = []
  /// Set when a replacement arrived that the page could not use: for a literal of a type without a live form, or a number
  /// its type cannot hold. The page then shows another value than the source, and must reload when the build ends.
  nonisolated(unsafe) static var unapplied = false
  /// True while the launcher builds the application's scene (`app.body`).
  nonisolated(unsafe) package static var launching = false
  /// The literals evaluated while the scene was built, outside any view's render. The scene and the values in it are built
  /// once and retained, so rendering again never runs these `_live` calls: a replacement for one needs a reload.
  nonisolated(unsafe) static var startupOnly: Set<UInt64> = []

  /// A new start of the application forgets the replacements: they were the page's values of literals of the module it
  /// ran before, and a hot swap keeps this framework module while it loads an application compiled with the values as
  /// they are now (an identifier is the literal's place in its file, which another build gives to another literal).
  package static func _startApplication() {
    table = .init()
    unsupported = []
    startupOnly = []
    unapplied = false
  }

  @inline(never) static func noteStartup(_ id: UInt64) {
    if StateRuntime.scope == nil { startupOnly.insert(id) }
  }

  /// Whether a replacement could not be used since the last call; the launcher asks after it rendered the replacements.
  package static func _takeUnapplied() -> Bool {
    defer { unapplied = false }
    return unapplied
  }

  /// Takes the replacements the development loop sent: lines of `id<TAB>kind<TAB>value`, where kind is `s`, `n` or `b`
  /// and a string's line breaks, tabs and backslashes are written `\n`, `\t` and `\\`. Returns how many were taken.
  @discardableResult public static func _apply(_ text: String) -> Int {
    var taken = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      guard fields.count == 3, let id = UInt64(fields[0]) else { continue }
      switch fields[1] {
      case "s": table[id] = .string(unescaped(fields[2]))
      case "n":
        // Kept as written; a text that is not a number is not a replacement.
        let number = String(fields[2])
        guard Double(number) != nil else { continue }
        table[id] = .number(number)
      case "b": table[id] = .bool(fields[2] == "true")
      default: continue
      }
      if unsupported.contains(id) || startupOnly.contains(id) { unapplied = true }
      taken += 1
    }
    return taken
  }

  private static func unescaped(_ text: Substring) -> String {
    var result = ""
    var escaped = false
    for character in text {
      if escaped {
        switch character {
        case "n": result.append("\n")
        case "t": result.append("\t")
        default: result.append(character)
        }
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else {
        result.append(character)
      }
    }
    return result
  }
}

public func _live<T: ExpressibleByStringLiteral & _LiveStringLiteral>(_ id: UInt64, _ literal: T) -> T {
  if _LiveLiterals.launching { _LiveLiterals.noteStartup(id) }
  if !_LiveLiterals.table.isEmpty, case .string(let value)? = _LiveLiterals.table[id] { return T._liveLiteral(value) }
  return literal
}

/// The types a one-character literal makes that a string literal does not (`Character`, `KeyEquivalent`). A type that
/// takes string literals uses the overload above, which is the more specific one.
public func _live<T: ExpressibleByExtendedGraphemeClusterLiteral & _LiveStringLiteral>(_ id: UInt64, _ literal: T) -> T {
  if _LiveLiterals.launching { _LiveLiterals.noteStartup(id) }
  if !_LiveLiterals.table.isEmpty, case .string(let value)? = _LiveLiterals.table[id] { return T._liveLiteral(value) }
  return literal
}

public func _live<T: ExpressibleByIntegerLiteral & _LiveNumberLiteral>(_ id: UInt64, _ literal: T) -> T {
  if _LiveLiterals.launching { _LiveLiterals.noteStartup(id) }
  if !_LiveLiterals.table.isEmpty, case .number(let text)? = _LiveLiterals.table[id] {
    if let value = T._liveLiteral(number: text) { return value }
    _LiveLiterals.unapplied = true
  }
  return literal
}

public func _live(_ id: UInt64, _ literal: Bool) -> Bool {
  if _LiveLiterals.launching { _LiveLiterals.noteStartup(id) }
  if !_LiveLiterals.table.isEmpty, case .bool(let value)? = _LiveLiterals.table[id] { return value }
  return literal
}

/// Any other literal (a type of the application's that takes literals, a `Decimal`): it stays as written. The lowering
/// cannot know a literal's type, so without this a file holding one would not compile in the development loop.
@_disfavoredOverload public func _live<T>(_ id: UInt64, _ literal: T) -> T {
  if _LiveLiterals.launching { _LiveLiterals.noteStartup(id) }
  // Remembered, so a replacement that arrives for this literal, or is already there, is known not to show.
  _LiveLiterals.unsupported.insert(id)
  if !_LiveLiterals.table.isEmpty, _LiveLiterals.table[id] != nil { _LiveLiterals.unapplied = true }
  return literal
}
