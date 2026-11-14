import Foundation
import Testing
@testable import Foundation

/// The Swift half of `NSPredicate`: how objects, arguments and variables are written for the browser host. The format
/// language itself runs in JavaScript (`Tools/BrowserIO/predicate-engine.mjs`) and is checked against Foundation's answers by
/// `Tools/test-predicate-engine.mjs`, which also decodes the bytes recorded here. A native host has no browser to ask, so
/// what is checked here is the bytes themselves; `EmbeddedPredicateFixture` runs both halves together in a browser.
@Suite(.processGlobalState)
@MainActor
final class WebFoundationPredicateTests {
  /// A class instance read by key, the way `NSObject.value(forKey:)` exposes it to a predicate.
  final class Person {
    let name: String
    let age: Int
    init(_ name: String, _ age: Int) {
      self.name = name
      self.age = age
    }

    func value(forKey key: String) -> Any? {
      switch key {
      case "name": return name
      case "age": return age
      default: return nil
      }
    }
  }

  /// What the Foundation layer does for class instances: describe them by the keys the predicate reads.
  static func foreign(names: [String], depth limit: Int) -> _PredicateWire.Foreign {
    { value, depth in
      if value is NSNull { return .null }
      guard let person = value as? Person else { return nil }
      guard depth < limit else { return .object(id: 7, properties: []) }
      return .object(id: 7, properties: names.map { ($0, person.value(forKey: $0)) })
    }
  }

  static let noForeign: _PredicateWire.Foreign = { _, _ in nil }

  @Test
  func classInstancesAreWrittenWithTheKeysThePredicateReads() {
    let alice = Person("Alice", 30)
    let wire = _PredicateWire.object(alice, foreign: Self.foreign(names: ["name", "age"], depth: 1))
    _expectEqual(wire, [9] + wireWord(7, bytes: 8) + wireCount(2) + wireText("name") + wireString("Alice") + wireText("age") + wireInteger(30))
    // Below the depth the predicate reads, an instance is only its identity.
    _expectEqual(_PredicateWire.object(alice, foreign: Self.foreign(names: ["name"], depth: 0)), [9] + wireWord(7, bytes: 8) + wireCount(0))
  }

  @Test
  func argumentsAreWrittenOneAfterAnotherAndVariablesAsOneSortedDictionary() {
    _expectEqual(_PredicateWire.arguments(["x", 0.5], foreign: Self.noForeign), wireString("x") + wireDouble(0.5))
    _expectEqual(_PredicateWire.arguments(nil, foreign: Self.noForeign), [])
    _expectEqual(
      _PredicateWire.bindings(["MIN": 5, "A": "a"], foreign: Self.noForeign),
      [8] + wireCount(2) + wireText("A") + wireString("a") + wireText("MIN") + wireInteger(5)
    )
  }

  /// A value that no Swift type and no foreign description covers.
  private struct Opaque: Equatable {
    let value: Int
  }

  @Test
  func valuesNothingDescribesAreWrittenAsNil() {
    _expectEqual(_PredicateWire.object(Opaque(value: 1), foreign: Self.noForeign), [0])
    _expectEqual(_PredicateWire.object(nil, foreign: Self.noForeign), [0])
  }

  @Test
  func foreignDescriptionsAreWrittenInTheirWireShape() {
    func describe(_ description: _PredicateForeign) -> [UInt8] {
      let foreign: _PredicateWire.Foreign = { value, _ in value is Opaque ? description : nil }
      return _PredicateWire.object(Opaque(value: 0), foreign: foreign)
    }
    // A replacement is read as the value that stands in for the object.
    _expectEqual(describe(.replacement(7)), wireInteger(7))
    _expectEqual(describe(.null), [1])
    _expectEqual(describe(.array([1, "a"])), [6] + wireCount(2) + wireInteger(1) + wireString("a"))
    _expectEqual(describe(.set(["x"])), [7] + wireCount(1) + wireString("x"))
    _expectEqual(describe(.dictionary([("k", 1)])), [8] + wireCount(1) + wireText("k") + wireInteger(1))
    _expectEqual(
      describe(.object(id: 9, properties: [("k", "v")])),
      [9] + wireWord(9, bytes: 8) + wireCount(1) + wireText("k") + wireString("v")
    )
  }

  @Test
  func nestingDeeperThanTheWireLimitStopsWithNil() {
    var nested: Any = 1
    for _ in 0..<70 { nested = [nested] }
    // The walk stops at level 64: 64 array headers (tag 6, one element each), then a nil.
    var expected: [UInt8] = []
    for _ in 0..<64 { expected += [6] + wireCount(1) }
    expected.append(0)
    _expectEqual(_PredicateWire.object(nested, foreign: Self.noForeign), expected)
  }

  @Test
  func everyNumericTypeHasOneWireEncoding() {
    _expectEqual(_PredicateWire.object(Int64.min, foreign: Self.noForeign), wireInteger(Int64.min))
    _expectEqual(_PredicateWire.object(Int32(-3), foreign: Self.noForeign), wireInteger(-3))
    _expectEqual(_PredicateWire.object(UInt(3), foreign: Self.noForeign), wireInteger(3))
    // Unsigned values above Int64.max cannot be integers in the core, so they travel as doubles.
    _expectEqual(_PredicateWire.object(UInt(UInt.max), foreign: Self.noForeign), wireDouble(Double(UInt.max)))
    _expectEqual(_PredicateWire.object(UInt64(5), foreign: Self.noForeign), wireInteger(5))
    _expectEqual(_PredicateWire.object(UInt32(7), foreign: Self.noForeign), wireInteger(7))
    _expectEqual(_PredicateWire.object(UInt16(8), foreign: Self.noForeign), wireInteger(8))
    _expectEqual(_PredicateWire.object(Int16(-9), foreign: Self.noForeign), wireInteger(-9))
    _expectEqual(_PredicateWire.object(Int8(-10), foreign: Self.noForeign), wireInteger(-10))
    _expectEqual(_PredicateWire.object(UInt8(11), foreign: Self.noForeign), wireInteger(11))
    // A Float widens to the Double it represents exactly, not to its decimal spelling.
    _expectEqual(_PredicateWire.object(Float(0.1), foreign: Self.noForeign), wireDouble(Double(Float(0.1))))
  }

  /// Every collection shape the writer recognises, with the bytes it produced before the typed branches were
  /// reordered. The bytes are the contract: the same expectations must hold whichever branch takes the value.
  @Test
  func collectionEncodingsAreByteIdenticalToTheRecordedWire() {
    let corpus: [(name: String, value: Any?, bytes: [UInt8])] = [
      ("empty array", [] as [Any], [6, 0, 0, 0, 0]),
      ("empty typed array", [] as [String], [6, 0, 0, 0, 0]),
      ("strings", ["a", "b"] as [String], [6, 2, 0, 0, 0, 4, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 98]),
      ("ints", [1, 2] as [Int], [6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0]),
      ("doubles", [1.5, -0.25] as [Double], [6, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 248, 63, 3, 0, 0, 0, 0, 0, 0, 208, 191]),
      ("bools", [true, false] as [Bool], [6, 2, 0, 0, 0, 10, 1, 10, 0]),
      ("dates", [Date(timeIntervalSince1970: 100)] as [Date], [6, 1, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 89, 64]),
      ("dictionary array", [["k": 1]] as [[String: Any]], [6, 1, 0, 0, 0, 8, 1, 0, 0, 0, 1, 0, 0, 0, 107, 2, 1, 0, 0, 0, 0, 0, 0, 0]),
      ("string set", Set(["x", "y"]), [7, 2, 0, 0, 0, 4, 1, 0, 0, 0, 120, 4, 1, 0, 0, 0, 121]),
      ("integer set", Set([2, 1]), [7, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0]),
      ("string dictionary", ["a": "x"] as [String: String], [8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 120]),
      ("integer dictionary", ["a": 1] as [String: Int], [8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 2, 1, 0, 0, 0, 0, 0, 0, 0]),
      ("double dictionary", ["a": 1.5] as [String: Double], [8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 3, 0, 0, 0, 0, 0, 0, 248, 63]),
      ("boolean dictionary", ["a": true] as [String: Bool], [8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 10, 1]),
      ("two-entry string dictionary", ["a": "x", "b": "y"] as [String: String], [8, 2, 0, 0, 0, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 120, 1, 0, 0, 0, 98, 4, 1, 0, 0, 0, 121]),
      ("two-entry integer dictionary", ["a": 1, "b": 2] as [String: Int], [8, 2, 0, 0, 0, 1, 0, 0, 0, 97, 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 98, 2, 2, 0, 0, 0, 0, 0, 0, 0]),
      ("two-entry double dictionary", ["a": 1.5, "b": -0.25] as [String: Double], [8, 2, 0, 0, 0, 1, 0, 0, 0, 97, 3, 0, 0, 0, 0, 0, 0, 248, 63, 1, 0, 0, 0, 98, 3, 0, 0, 0, 0, 0, 0, 208, 191]),
      ("two-entry boolean dictionary", ["a": true, "b": false] as [String: Bool], [8, 2, 0, 0, 0, 1, 0, 0, 0, 97, 10, 1, 1, 0, 0, 0, 98, 10, 0]),
      ("mixed integer and double", [1, 2.5] as [Any], [6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 4, 64]),
      ("strings held as Any", ["a", "b"] as [Any], [6, 2, 0, 0, 0, 4, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 98]),
      ("optional with nil", [1, nil] as [Any?], [6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0]),
      ("optional strings", ["a", "b"] as [Any?], [6, 2, 0, 0, 0, 4, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 98]),
      ("nested arrays", [[1, 2], ["x"]] as [Any], [6, 2, 0, 0, 0, 6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 6, 1, 0, 0, 0, 4, 1, 0, 0, 0, 120]),
      (
        "dictionaries in an array",
        [["a": 1], ["b": 2]] as [Any],
        [6, 2, 0, 0, 0, 8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 2, 1, 0, 0, 0, 0, 0, 0, 0, 8, 1, 0, 0, 0, 1, 0, 0, 0, 98, 2, 2, 0, 0, 0, 0, 0, 0, 0]
      ),
      (
        "mixed dictionary",
        ["a": "x", "b": 2] as [String: Any],
        [8, 2, 0, 0, 0, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 120, 1, 0, 0, 0, 98, 2, 2, 0, 0, 0, 0, 0, 0, 0]
      ),
      ("dictionary holding an array", ["k": [1, 2]] as [String: Any], [8, 1, 0, 0, 0, 1, 0, 0, 0, 107, 6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0]),
      ("dictionary holding a dictionary", ["k": ["a": "x"]] as [String: Any], [8, 1, 0, 0, 0, 1, 0, 0, 0, 107, 8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 120]),
      ("dictionary of strings held as Any", ["a": "x"] as [String: Any], [8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 120]),
      ("array of a set", [Set([1])] as [Any], [6, 1, 0, 0, 0, 7, 1, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0]),
      (
        "deep mixed",
        [["x": [1, "y"]], 3] as [Any],
        [6, 2, 0, 0, 0, 8, 1, 0, 0, 0, 1, 0, 0, 0, 120, 6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 4, 1, 0, 0, 0, 121, 2, 3, 0, 0, 0, 0, 0, 0, 0]
      ),
    ]
    for entry in corpus {
      let bytes = _PredicateWire.object(entry.value, foreign: Self.noForeign)
      #expect(bytes == entry.bytes, Comment(rawValue: "\(entry.name): \(bytes)"))
    }
  }

  @Test
  func charactersSubstringsAndIntegerSetsHaveTheirOwnWireShapes() {
    _expectEqual(_PredicateWire.object(Character("é"), foreign: Self.noForeign), wireString("é"))
    _expectEqual(_PredicateWire.object("hello".dropFirst(), foreign: Self.noForeign), wireString("ello"))
    // A set is written in ascending order, so equal sets have one encoding.
    _expectEqual(
      _PredicateWire.object(Set([3, 1, 2]), foreign: Self.noForeign),
      [7] + wireCount(3) + wireInteger(1) + wireInteger(2) + wireInteger(3)
    )
  }
}

// MARK: Wire encodings used by the expectations above

private func wireWord(_ value: UInt64, bytes count: Int) -> [UInt8] {
  (0..<count).map { UInt8(truncatingIfNeeded: value >> UInt64(8 * $0)) }
}

private func wireCount(_ value: Int) -> [UInt8] { wireWord(UInt64(value), bytes: 4) }

private func wireText(_ value: String) -> [UInt8] { wireCount(value.utf8.count) + Array(value.utf8) }

private func wireString(_ value: String) -> [UInt8] { [4] + wireText(value) }

private func wireInteger(_ value: Int64) -> [UInt8] { [2] + wireWord(UInt64(bitPattern: value), bytes: 8) }

private func wireDouble(_ value: Double) -> [UInt8] { [3] + wireWord(value.bitPattern, bytes: 8) }
