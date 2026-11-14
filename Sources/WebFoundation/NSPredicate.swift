// Foundation's `NSPredicate` for browser and Embedded builds. The format language (Apple's Predicate
// Programming Guide: comparisons, BETWEEN, the string operators with their [cdnl] options, IN, ANY / ALL /
// NONE, key paths with @count / @sum / @avg / @min / @max, SELF, $VARIABLES, aggregates, arithmetic and the
// %@ %K %d %f ... arguments) is parsed and evaluated by the browser host (`Tools/BrowserIO/predicate-engine.mjs`,
// BrowserIO's `predicate` operation); `PredicateEngine.swift` hands it the object as a flat buffer. Objects are read
// without reflection: dictionaries, arrays, sets, strings, numbers, dates, `NSArray`, `NSNumber`, `NSNull`, and class
// instances through `NSObject.value(forKey:)`.
//
// Where Foundation raises an Objective-C exception, this class cannot: a format that does not parse stops
// the program with `preconditionFailure`, and a predicate that raises while evaluating (an ordering of unlike
// types, an unbound `$VARIABLE`, an invalid `MATCHES` pattern) evaluates to `false`.
// Not supported: function expressions (`FUNCTION(..)`, `lowercase:`), `SUBQUERY`, index expressions (`a[0]`),
// `NSExpression`, `NSComparisonPredicate` and `NSCompoundPredicate`, secure coding.
@_spi(Renderer) import SwiftUIWebBrowserIO
import SwiftUIWebCore

/// Foundation's `CVarArg`, the protocol Apple's variadic format arguments take. Embedded Swift does not ship it,
/// so it is a marker here; the predicate reads the argument types it knows (integers, floating point numbers,
/// strings, dates, arrays, sets, `NSNumber`, `NSNull` and objects).
public protocol CVarArg {}
extension String: CVarArg {}
extension Int: CVarArg {}
extension Int8: CVarArg {}
extension Int16: CVarArg {}
extension Int32: CVarArg {}
extension Int64: CVarArg {}
extension UInt: CVarArg {}
extension UInt8: CVarArg {}
extension UInt16: CVarArg {}
extension UInt32: CVarArg {}
extension UInt64: CVarArg {}
extension Double: CVarArg {}
extension Float: CVarArg {}
extension Bool: CVarArg {}
extension Date: CVarArg {}
extension Array: CVarArg {}
extension Set: CVarArg {}
extension NSObject: CVarArg {}
extension NSNumber: CVarArg {}

/// A predicate whose format language the browser host runs (`BrowserPredicate`). Swift keeps what the host needs to rebuild it
/// (the format and the argument and variable values as wire bytes), because the host that parsed it can be replaced while the
/// application keeps running; the host keeps the parsed form under `id`.
@_spi(Renderer) public struct _CompiledPredicate {
  private let id: UInt32
  private let format: String
  private let arguments: [UInt8]
  private let bindings: [UInt8]
  private let constant: Bool?
  /// `predicateFormat`.
  public let predicateFormat: String
  /// The key names a class instance is read for, and the longest key path (in keys, operators excluded).
  public let keys: (names: [String], depth: Int)

  private init(_ id: UInt32, _ format: String, _ arguments: [UInt8], _ bindings: [UInt8], _ found: BrowserPredicate.Description) {
    self.id = id
    self.format = format
    self.arguments = arguments
    self.bindings = bindings
    self.constant = nil
    self.predicateFormat = found.format
    self.keys = (found.keyNames, found.keyDepth)
  }

  private init(constant value: Bool) {
    self.id = 0
    self.format = ""
    self.arguments = []
    self.bindings = []
    self.constant = value
    self.predicateFormat = value ? "TRUEPREDICATE" : "FALSEPREDICATE"
    self.keys = ([], 0)
  }

  /// Parses `format`, replacing its `%` conversions with `arguments` (wire values, one after another).
  /// Nil when Foundation would raise for the format.
  public static func parse(format: String, arguments: [UInt8]) -> _CompiledPredicate? {
    let id = BrowserPredicate.makeIdentifier()
    guard let found = BrowserPredicate.describe(id: id, format: format, arguments: arguments, bindings: []) else { return nil }
    return _CompiledPredicate(id, format, arguments, [], found)
  }

  /// `TRUEPREDICATE` or `FALSEPREDICATE`.
  public static func constant(_ value: Bool) -> _CompiledPredicate { _CompiledPredicate(constant: value) }

  /// `withSubstitutionVariables(_:)`: `bindings` is one wire dictionary.
  public func substituting(bindings more: [UInt8]) -> _CompiledPredicate? {
    guard constant == nil else { return self }
    let id = BrowserPredicate.makeIdentifier()
    let all = bindings + more
    guard let found = BrowserPredicate.describe(id: id, format: format, arguments: arguments, bindings: all) else { return nil }
    return _CompiledPredicate(id, format, arguments, all, found)
  }

  /// Evaluates the predicate with `object` (one wire value) as `SELF`; nil when Foundation would raise.
  public func evaluate(object: [UInt8]) -> Bool? {
    if let constant { return constant }
    return BrowserPredicate.evaluate(id: id, format: format, arguments: arguments, bindings: bindings, object: object)
  }
}

open class NSPredicate: NSObject {
  private let _compiled: _CompiledPredicate?
  private let _block: ((Any?, [String: Any]?) -> Bool)?
  private let _keyNames: [String]
  private let _keyDepth: Int

  /// Wraps a compiled predicate; `withSubstitutionVariables(_:)` builds its `Self` through this.
  @_spi(Renderer) public required init(_compiled: _CompiledPredicate?, block: ((Any?, [String: Any]?) -> Bool)?) {
    let keys = _compiled?.keys ?? (names: [], depth: 0)
    self._compiled = _compiled
    self._block = block
    self._keyNames = keys.names
    self._keyDepth = keys.depth
    super.init()
  }

  /// Parses `predicateFormat`, replacing its `%` conversions with `arguments`. A format that does not parse
  /// stops the program, where Foundation raises `NSInvalidArgumentException`.
  public init(format predicateFormat: String, argumentArray arguments: [Any]?) {
    guard let compiled = NSPredicate._compile(predicateFormat, arguments) else {
      preconditionFailure("Unable to parse the format string \"\(predicateFormat)\"")
    }
    let keys = compiled.keys
    self._compiled = compiled
    self._block = nil
    self._keyNames = keys.names
    self._keyDepth = keys.depth
    super.init()
  }

  public convenience init(format predicateFormat: String, _ args: any CVarArg...) {
    self.init(format: predicateFormat, argumentArray: args.map { $0 as Any })
  }

  /// A predicate that is always `value`.
  public init(value: Bool) {
    self._compiled = _CompiledPredicate.constant(value)
    self._block = nil
    self._keyNames = []
    self._keyDepth = 0
    super.init()
  }

  /// A predicate that asks `block`. Its `predicateFormat` is `BLOCKPREDICATE(0x…)`.
  public init(block: @escaping (Any?, [String: Any]?) -> Bool) {
    self._compiled = nil
    self._block = block
    self._keyNames = []
    self._keyDepth = 0
    super.init()
  }


  private static func _compile(_ format: String, _ arguments: [Any]?) -> _CompiledPredicate? {
    _CompiledPredicate.parse(format: format, arguments: _PredicateWire.arguments(arguments, foreign: _foreign(names: [], depth: 0)))
  }

  open var predicateFormat: String {
    if let compiled = _compiled { return compiled.predicateFormat }
    return "BLOCKPREDICATE(0x" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16) + ")"
  }

  /// A copy in which each `$NAME` bound in `variables` is replaced by its value; other variables stay.
  open func withSubstitutionVariables(_ variables: [String: Any]) -> Self {
    guard let compiled = _compiled else { return self }
    let wire = _PredicateWire.bindings(variables, foreign: NSPredicate._foreign(names: [], depth: 0))
    guard let substituted = compiled.substituting(bindings: wire) else { return self }
    return Self(_compiled: substituted, block: nil)
  }

  /// Whether `object` satisfies the predicate. A predicate that raises in Foundation evaluates to `false`.
  open func evaluate(with object: Any?) -> Bool {
    if let block = _block { return block(object, nil) }
    guard let compiled = _compiled else { return false }
    let wire = _PredicateWire.object(object, foreign: NSPredicate._foreign(names: _keyNames, depth: _keyDepth))
    return compiled.evaluate(object: wire) ?? false
  }

  open func evaluate(with object: Any?, substitutionVariables bindings: [String: Any]?) -> Bool {
    guard let bindings else { return evaluate(with: object) }
    if let block = _block { return block(object, bindings) }
    return withSubstitutionVariables(bindings).evaluate(with: object)
  }

  /// Foundation uses this to re-enable evaluation of a securely decoded predicate; nothing here is blocked.
  open func allowEvaluation() {}

  /// Describes the values Swift's built-in types do not: `NSNull`, `NSNumber`, `NSArray` and class instances,
  /// whose keys the predicate reads through `value(forKey:)` down to the depth its key paths reach.
  fileprivate static func _foreign(names: [String], depth limit: Int) -> _PredicateWire.Foreign {
    return { value, depth in
      // Embedded Swift emits a class's initializers and deinitializer only when something allocates it, yet the
      // casts below need its metadata, which refers to them: an application that never creates an `NSNumber`
      // would fail to link. Allocations on a path that never runs keep them (`depth` is never negative).
      if depth < 0 { return .array([NSNumber(value: 0), NSArray(), NSNull()]) }
      if let number = value as? NSNumber { return .replacement(number._predicateValue) }
      if let array = value as? NSArray { return .array(array._items.map { Optional($0) }) }
      guard let object = value as? NSObject else { return nil }
      if object is NSNull { return .null }
      let identity = UInt64(UInt(bitPattern: ObjectIdentifier(object).hashValue))
      guard depth < limit else { return .object(id: identity, properties: []) }
      return .object(id: identity, properties: names.map { ($0, object.value(forKey: $0)) })
    }
  }
}
