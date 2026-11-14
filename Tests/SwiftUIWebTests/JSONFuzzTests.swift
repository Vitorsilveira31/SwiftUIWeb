import Testing
import Foundation
@testable import SwiftUIWeb

/// A seeded fuzz of the JSON parser behind `JSONDecoder` and `JSONSerialization`: documents generated at random parse
/// back to what was written, and mutated or truncated documents are answered (a value or an error) without trapping or
/// hanging. The seed is fixed so a failure reproduces; `SWIFTUIWEB_JSON_FUZZ_SEED` and `..._COUNT` widen a local run.
/// The browser build, where `Int` is 32 bits, runs the same mutations in `make hostile-values-browser-test` (json-fuzz).
@Suite
struct JSONFuzzTests {
  struct Generator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  indirect enum Value: Equatable {
    case null, bool(Bool), int(Int64), double(Double), string(String), array([Value]), object([String: Value])
  }

  static func value(_ random: inout Generator, depth: Int) -> Value {
    switch Int.random(in: 0 ..< (depth > 4 ? 5 : 7), using: &random) {
    case 0: return .null
    case 1: return .bool(Bool.random(using: &random))
    case 2: return .int([0, 1, -1, Int64(Int32.max), Int64(Int32.max) + 1, 9_007_199_254_740_991, Int64.random(in: -1_000_000 ... 1_000_000, using: &random)].randomElement(using: &random)!)
    case 3: return .double([0.5, -1e-300, 1e300, 3e9 + 0.25, Double.random(in: -1e6 ... 1e6, using: &random)].randomElement(using: &random)!)
    case 4: return .string(string(&random))
    case 5: return .array((0 ..< Int.random(in: 0 ... 4, using: &random)).map { _ in value(&random, depth: depth + 1) })
    default:
      var object: [String: Value] = [:]
      for _ in 0 ..< Int.random(in: 0 ... 4, using: &random) { object[string(&random)] = value(&random, depth: depth + 1) }
      return .object(object)
    }
  }

  static func string(_ random: inout Generator) -> String {
    let pieces = ["a", "é", "\"", "\\", "/", "\n", "\t", "\u{0}", "\u{1F}", "😀", "\u{FFFC}", "𝄞", "ß", " "]
    return (0 ..< Int.random(in: 0 ... 6, using: &random)).map { _ in pieces.randomElement(using: &random)! }.joined()
  }

  static func write(_ value: Value) -> String {
    switch value {
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .int(let number): return String(number)
    case .double(let number): return "\(number)"
    case .string(let text): return quote(text)
    case .array(let items): return "[" + items.map(write).joined(separator: ",") + "]"
    case .object(let members): return "{" + members.keys.sorted().map { quote($0) + ":" + write(members[$0]!) }.joined(separator: ",") + "}"
    }
  }

  static func quote(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          let hex = String(scalar.value, radix: 16)
          out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out + "\""
  }

  /// The value `JSONSerialization` read, in the generator's terms.
  static func read(_ object: Any) -> Value? {
    if object is NSNull { return .null }
    if let flag = object as? Bool { return .bool(flag) }
    if let number = object as? Int { return .int(Int64(number)) }
    if let number = object as? Double { return .double(number) }
    if let text = object as? String { return .string(text) }
    if let items = object as? [Any] {
      var values: [Value] = []
      for item in items { guard let value = read(item) else { return nil }; values.append(value) }
      return .array(values)
    }
    if let members = object as? [String: Any] {
      var values: [String: Value] = [:]
      for (key, item) in members { guard let value = read(item) else { return nil }; values[key] = value }
      return .object(values)
    }
    return nil
  }

  /// A whole double and an integer of the same value are the same JSON number.
  static func same(_ a: Value, _ b: Value) -> Bool {
    switch (a, b) {
    case (.int(let x), .double(let y)), (.double(let y), .int(let x)): return Double(x) == y
    case (.array(let x), .array(let y)): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
    case (.object(let x), .object(let y)): return x.keys.sorted() == y.keys.sorted() && x.keys.allSatisfy { same(x[$0]!, y[$0]!) }
    default: return a == b
    }
  }

  static func mutate(_ text: String, _ random: inout Generator) -> [UInt8] {
    var bytes = Array(text.utf8)
    let alphabet = Array("{}[]\",:0123456789-+.eE\\u\u{0}tfn ".utf8) + [0xFF, 0xC3, 0xED, 0xA0, 0x80]
    for _ in 0 ..< Int.random(in: 1 ... 4, using: &random) {
      switch Int.random(in: 0 ..< 5, using: &random) {
      case 0 where !bytes.isEmpty: bytes[Int.random(in: 0 ..< bytes.count, using: &random)] = alphabet.randomElement(using: &random)!
      case 1: bytes.insert(alphabet.randomElement(using: &random)!, at: Int.random(in: 0 ... bytes.count, using: &random))
      case 2 where !bytes.isEmpty: bytes.removeLast(Int.random(in: 1 ... bytes.count, using: &random))
      case 3: bytes = Array(repeating: UInt8(ascii: "["), count: Int.random(in: 1 ... 3_000, using: &random)) + bytes
      default: bytes += Array("1e99999".utf8)
      }
    }
    return bytes
  }

  private var seed: UInt64 { UInt64(ProcessInfo.processInfo.environment["SWIFTUIWEB_JSON_FUZZ_SEED"] ?? "") ?? 0x5EED_0001 }
  private var count: Int { Int(ProcessInfo.processInfo.environment["SWIFTUIWEB_JSON_FUZZ_COUNT"] ?? "") ?? 3_000 }

  struct Document: Decodable { var a: Int?; var b: [Double]?; var c: String?; var d: [String: Int64]? }

  @Test
  func generatedDocumentsParseBackToTheirValues() throws {
    var random = Generator(state: seed)
    for round in 0 ..< count {
      let value = Self.value(&random, depth: 0)
      let text = Self.write(value)
      let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
      let read = try #require(Self.read(object), "round \(round), seed \(seed): \(text)")
      #expect(Self.same(read, value), "round \(round), seed \(seed): \(text)")
    }
  }

  @Test
  func mutatedDocumentsAreAnsweredWithoutTrapping() {
    var random = Generator(state: seed &+ 1)
    var parsed = 0, refused = 0
    for _ in 0 ..< count {
      let bytes = Self.mutate(Self.write(Self.value(&random, depth: 0)), &random)
      if (try? JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])) != nil { parsed += 1 } else { refused += 1 }
      _ = try? JSONDecoder().decode(Document.self, from: Data(bytes))
      _ = try? JSONDecoder().decode([Document].self, from: Data(bytes))
    }
    #expect(parsed + refused == count)
    #expect(refused > 0)
  }
}
