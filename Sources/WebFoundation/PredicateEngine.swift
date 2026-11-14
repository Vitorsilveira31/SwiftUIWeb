// How the values a predicate compares reach the browser host. Embedded Swift has no reflection, so
// Swift flattens the object under test into a byte buffer (`_PredicateWire`) and the host evaluates it;
// nothing calls back into Swift. This file is compiled on every host so native tests cover it; the
// `NSPredicate` class that uses it exists only where Foundation does not.
//
// The wire format is the one `Tools/BrowserIO/predicate-engine.mjs` reads: a tag byte, then
// 0 nil, 1 NSNull, 2 i64, 3 f64 bits, 4 string (u32 length, UTF-8), 5 date (f64 bits, seconds since 1970),
// 6 array and 7 set (u32 count, values), 8 dictionary (u32 count, key string, value), 9 class instance
// (u64 identity, then a dictionary), 10 boolean (one byte). Everything is little endian.
import SwiftUIWebCore

/// A value that Swift's built-in types cannot describe and the Foundation layer therefore does.
package enum _PredicateForeign {
  /// `NSNull`.
  case null
  /// Another value stands in for this one (an `NSNumber` is the number it holds).
  case replacement(Any)
  case array([Any?])
  case set([Any?])
  case dictionary([(String, Any?)])
  /// A class instance: equal only to itself, read by key. `properties` is empty when the predicate
  /// never reads below this depth.
  case object(id: UInt64, properties: [(String, Any?)])
}

package struct _PredicateWire {
  package private(set) var bytes: [UInt8] = []

  /// Answers for values that are not Swift's own; nil when `value` is not one of those either. `depth` is the
  /// number of keys read to reach the value from the object under test (elements of a collection add none).
  package typealias Foreign = (_ value: Any, _ depth: Int) -> _PredicateForeign?

  package init() {}

  /// One value, as the evaluator's `SELF`.
  package static func object(_ value: Any?, foreign: Foreign) -> [UInt8] {
    var wire = _PredicateWire()
    wire.append(value, depth: 0, level: 0, foreign: foreign)
    return wire.bytes
  }

  /// The arguments of `NSPredicate(format:argumentArray:)`; `nil` is `NSNull`.
  package static func arguments(_ values: [Any]?, foreign: Foreign) -> [UInt8] {
    var wire = _PredicateWire()
    for value in values ?? [] { wire.append(value, depth: 0, level: 0, foreign: foreign) }
    return wire.bytes
  }

  /// The substitution variables, as one dictionary.
  package static func bindings(_ values: [String: Any], foreign: Foreign) -> [UInt8] {
    var wire = _PredicateWire()
    wire.byte(8)
    wire.count(values.count)
    for (name, value) in values.sorted(by: { $0.key < $1.key }) {
      wire.string(name)
      wire.append(value, depth: 1, level: 1, foreign: foreign)
    }
    return wire.bytes
  }

  // MARK: Writing

  private mutating func byte(_ value: UInt8) { bytes.append(value) }

  private mutating func count(_ value: Int) { word32(UInt32(truncatingIfNeeded: value)) }

  private mutating func word32(_ value: UInt32) {
    for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
  }

  private mutating func word64(_ value: UInt64) {
    for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift))) }
  }

  private mutating func string(_ value: String) {
    let utf8 = Array(value.utf8)
    count(utf8.count)
    bytes.append(contentsOf: utf8)
  }

  private mutating func integer(_ value: Int64) {
    byte(2)
    word64(UInt64(bitPattern: value))
  }

  private mutating func double(_ value: Double) {
    byte(3)
    word64(value.bitPattern)
  }

  private mutating func sequence(_ tag: UInt8, _ items: [Any?], depth: Int, level: Int, foreign: Foreign) {
    byte(tag)
    count(items.count)
    for item in items { append(item, depth: depth, level: level + 1, foreign: foreign) }
  }

  private mutating func dictionary(_ entries: [(String, Any?)], depth: Int, level: Int, foreign: Foreign) {
    count(entries.count)
    for (key, value) in entries {
      string(key)
      append(value, depth: depth + 1, level: level + 1, foreign: foreign)
    }
  }

  /// `depth` counts keys read from the object under test; `level` counts every nesting step, which also
  /// stops a collection that contains itself.
  private mutating func append(_ value: Any?, depth: Int, level: Int, foreign: Foreign) {
    guard let value else { return byte(0) }
    guard level < 64 else { return byte(0) }
    if appendScalar(value) { return }
    if appendCollection(value, depth: depth, level: level, foreign: foreign) { return }
    guard let described = foreign(value, depth) else { return byte(0) }
    switch described {
    case .null: byte(1)
    case .replacement(let other): append(other, depth: depth, level: level + 1, foreign: foreign)
    case .array(let items): sequence(6, items, depth: depth, level: level, foreign: foreign)
    case .set(let items): sequence(7, items, depth: depth, level: level, foreign: foreign)
    case .dictionary(let entries):
      byte(8)
      dictionary(entries, depth: depth, level: level, foreign: foreign)
    case .object(let id, let properties):
      byte(9)
      word64(id)
      dictionary(properties, depth: depth, level: level, foreign: foreign)
    }
  }

  /// Booleans, integers, floating point numbers, strings and dates.
  private mutating func appendScalar(_ value: Any) -> Bool {
    if let text = value as? String {
      byte(4)
      string(text)
    } else if let flag = value as? Bool {
      byte(10)
      byte(flag ? 1 : 0)
    } else if let number = value as? Int {
      integer(Int64(number))
    } else if let number = value as? Double {
      double(number)
    } else if let number = value as? Int64 {
      integer(number)
    } else if let number = value as? Int32 {
      integer(Int64(number))
    } else if let number = value as? UInt {
      if number > UInt(Int64.max) { double(Double(number)) } else { integer(Int64(number)) }
    } else if let number = value as? UInt64 {
      if number > UInt64(Int64.max) { double(Double(number)) } else { integer(Int64(number)) }
    } else if let number = value as? UInt32 {
      integer(Int64(number))
    } else if let number = value as? Int16 {
      integer(Int64(number))
    } else if let number = value as? UInt16 {
      integer(Int64(number))
    } else if let number = value as? Int8 {
      integer(Int64(number))
    } else if let number = value as? UInt8 {
      integer(Int64(number))
    } else if let number = value as? Float {
      double(Double(number))
    } else if let date = value as? Date {
      byte(5)
      word64(date.timeIntervalSince1970.bitPattern)
    } else if let character = value as? Character {
      byte(4)
      string(String(character))
    } else if let text = value as? Substring {
      byte(4)
      string(String(text))
    } else {
      return false
    }
    return true
  }

  /// The collection types Embedded Swift can recognise without reflection.
  private mutating func appendCollection(_ value: Any, depth: Int, level: Int, foreign: Foreign) -> Bool {
    // Typed collections come first: a value of type `[String]` also casts to `[Any]` on hosts with
    // runtime casts, so the generic branches must be last for the typed ones to be reachable. Each branch
    // writes the same bytes as the generic one would for the same elements.
    if let items = value as? [String] {
      sequence(6, items.map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? [Int] {
      sequence(6, items.map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? [Double] {
      sequence(6, items.map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? [Bool] {
      sequence(6, items.map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? [Date] {
      sequence(6, items.map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? [[String: Any]] {
      sequence(6, items.map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? Set<String> {
      sequence(7, items.sorted().map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let items = value as? Set<Int> {
      sequence(7, items.sorted().map { $0 }, depth: depth, level: level, foreign: foreign)
    } else if let entries = value as? [String: String] {
      byte(8)
      dictionary(entries.sorted(by: { $0.key < $1.key }).map { ($0.key, Optional($0.value)) }, depth: depth, level: level, foreign: foreign)
    } else if let entries = value as? [String: Int] {
      byte(8)
      dictionary(entries.sorted(by: { $0.key < $1.key }).map { ($0.key, Optional($0.value)) }, depth: depth, level: level, foreign: foreign)
    } else if let entries = value as? [String: Double] {
      byte(8)
      dictionary(entries.sorted(by: { $0.key < $1.key }).map { ($0.key, Optional($0.value)) }, depth: depth, level: level, foreign: foreign)
    } else if let entries = value as? [String: Bool] {
      byte(8)
      dictionary(entries.sorted(by: { $0.key < $1.key }).map { ($0.key, Optional($0.value)) }, depth: depth, level: level, foreign: foreign)
    // Both generic casts stay: Embedded does not match `[Any]` and `[Any?]` with each other. Native hosts always
    // take the first, so the second is evaluated only where the first fails; one condition keeps the line reachable.
    } else if let items = (value as? [Any]).map({ $0.map { Optional($0) } }) ?? (value as? [Any?]) {
      sequence(6, items, depth: depth, level: level, foreign: foreign)
    } else if let entries = value as? [String: Any] {
      byte(8)
      dictionary(entries.sorted(by: { $0.key < $1.key }).map { ($0.key, Optional($0.value)) }, depth: depth, level: level, foreign: foreign)
    } else {
      return false
    }
    return true
  }
}
