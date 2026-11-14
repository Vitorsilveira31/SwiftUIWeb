import Foundation
import Testing

/// The Embedded JSON codec accepts strict RFC 8259 JSON, refuses everything else, and writes compact, key-sorted bytes.
@Suite struct EmbeddedJSONTests {
  private func parse(_ text: String) throws -> EmbeddedJSONValue { try parse(Array(text.utf8)) }
  private func parse(_ bytes: [UInt8]) throws -> EmbeddedJSONValue { try EmbeddedJSONCodec._parse(Data(bytes)) }
  private func compact(_ text: String) throws -> String { String(decoding: try EmbeddedJSONCodec._encode(try parse(text)), as: UTF8.self) }
  private func nested(_ open: String, _ close: String, _ depth: Int) -> String { String(repeating: open, count: depth) + "1" + String(repeating: close, count: depth) }

  @Test func acceptsValidDocuments() throws {
    let accepted: [(String, String)] = [
      ("[]", "[]"), ("{}", "{}"), (" \t\r\n[ \n]\r\n", "[]"), ("[ 1 , 2 ]", "[1,2]"), ("[true,false,null]", "[true,false,null]"),
      ("1", "1"), ("\"x\"", "\"x\""), ("null", "null"), ("  true  ", "true"), ("[[],{},[[]]]", "[[],{},[[]]]"),
      ("[0]", "[0]"), ("[-0]", "[0]"), ("[-1]", "[-1]"), ("[0.5]", "[0.5]"), ("[1e2]", "[100]"), ("[1E+2]", "[100]"), ("[1e-2]", "[0.01]"),
      ("[-1.5e1]", "[-15]"), ("[123e-2]", "[1.23]"), ("[0.1e1]", "[1]"), ("[0e0]", "[0]"), ("[0.000001]", "[1e-6]"), ("[9007199254740993]", "[9007199254740992]"),
      ("[1e-400]", "[0]"),
      (#"["a\"b\\c\/d\b\f\n\r\t"]"#, #"["a\"b\\c/d\b\f\n\r\t"]"#), (#"["\u0041\u00e9\u20AC\u12aB"]"#, "[\"A\u{E9}\u{20AC}\u{12AB}\"]"),
      (#"["\uD83D\uDE00"]"#, "[\"\u{1F600}\"]"), (#"["\ud83d\ude00\uDBFF\uDFFF"]"#, "[\"\u{1F600}\u{10FFFF}\"]"), (#"["\u0000\u001f\u007f"]"#, "[\"\\u0000\\u001f\u{7F}\"]"),
      (#"["\uFFFF\uE000\uD7FF"]"#, "[\"\u{FFFF}\u{E000}\u{D7FF}\"]"), ("[\"\u{E9}\u{65E5}\u{672C}\u{1F600}\u{2028}\u{7F}\"]", "[\"\u{E9}\u{65E5}\u{672C}\u{1F600}\u{2028}\u{7F}\"]"),
      (#"{"b":1,"a":[2,{"c":null}]}"#, #"{"a":[2,{"c":null}],"b":1}"#), (#"{"a":1,"a":2}"#, #"{"a":2}"#), (#"{"":0}"#, #"{"":0}"#), (#"{"a\n":1}"#, #"{"a\n":1}"#),
    ]
    for (input, expected) in accepted { #expect(try compact(input) == expected, "\(input)") }
  }

  @Test func numbersKeepTheirValue() throws {
    let numbers: [(String, Double)] = [
      ("1.7976931348623157e308", .greatestFiniteMagnitude), ("-1.7976931348623157e308", -.greatestFiniteMagnitude), ("5e-324", 5e-324),
      ("4.9e-324", 5e-324), ("0.1", 0.1), ("123456789012345678", 123_456_789_012_345_680), ("1e22", 1e22), ("1e23", 1e23), ("2.2250738585072014e-308", 2.2250738585072014e-308),
      ("0.30000000000000004", 0.30000000000000004), ("123456789.123456789e-5", 1234.56789123456789), ("100000000000000000000000000000", 1e29),
      ("12345678901234567890123", 1.2345678901234568e22), ("9007199254740993", 9_007_199_254_740_992), ("0.000000000000000000000000000001", 1e-30), ("-0", -0.0),
    ]
    for (input, expected) in numbers {
      guard case .number(let value) = try parse(input) else { Issue.record("\(input) is not a number"); continue }
      #expect(value == expected && value.sign == expected.sign, "\(input)")
    }
  }

  @Test func rejectsInvalidDocuments() {
    let rejected = [
      "", " ", "[", "]", "{", "}", "[1,]", "[,1]", "[1 2]", "[1,,2]", #"{"a":1,}"#, "{,}", #"{"a"}"#, #"{"a":}"#, "{a:1}", "{'a':1}", "{1:1}", #"{"a" 1}"#, #"{"a":1 "b":2}"#,
      #"{"a":1:2}"#, #"{"a":1"#, #"{"a":1,"#, #"{"a":"#, #"{"a""#, #"{""#, #"{"a":1}}"#, "[1]]", "[1]x", "[] []", "1 2", "[1;2]",
      "nul", "nulll", "True", "NULL", "tru", "[tru]", "[nul]", "truefalse", "[undefined]", "[NaN]", "[Infinity]", "[-Infinity]", "NaN", "-",
      "[01]", "[-01]", "[00]", "[+1]", "[.5]", "[1.]", "[1.e1]", "[1e]", "[1e+]", "[1E-]", "[--1]", "[1-]", "[0x10]", "[1_000]", "[1,2", "[1e400]", "[-1e400]", "[1 e5]", "[- 1]", "[1e1.5]",
      #"["a]"#, "\"abc", "['a']", #"["\x"]"#, #"["\"]"#, #"["\u12"]"#, #"["\u12G4"]"#, #"["\u+123"]"#, #"["\U0041"]"#, #"["\u"#, #"["\"#, #"["\ "]"#,
      #"["\uD800"]"#, #"["\uDC00"]"#, #"["\uD800\u0041"]"#, #"["\uD800x"]"#, #"["\uD800\"]"#, #"["\uDC00\uD800"]"#, #"["\uDBFF\uDBFF"]"#, #"["\uD800\uD800"]"#, #"["\uD800\n"]"#, #"["\uDFFF"]"#,
      "[\"\t\"]", "[\"\n\"]", "[\"\u{1F}\"]", "[\"\u{0}\"]", "[1]//x", "/*x*/[1]", "[1,/*x*/2]", "# x\n[1]", "\u{FEFF}[1]", "[\u{A0}1]", "\u{B}[1]", "[1]\u{C}", "[1]\u{0}", "[1,\u{0}]", "\u{2028}[1]", "[\u{3000}]",
      #"{"a":1}"x"#, "[\"a\"\"b\"]", "[1\"a\"]", "{[]:1}", "{null:1}", #"{"a":1,"b"}"#, "[,]", "{:}", "[:]", #"{"a"::1}"#,
    ]
    for input in rejected { #expect(throws: EmbeddedCodableError.self, "\(input.debugDescription)") { try parse(input) } }
  }

  /// Integer fields convert the parsed Double exactly: a fraction or a value outside the target type is refused. `Int(Double)`
  /// trapped outside the range and silently truncated a fraction (1.9 became 1).
  @Test func integerDecodersRefuseNumbersTheyCannotRepresent() {
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int.self, from: Data("1.9".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int.self, from: Data("-1.5".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int.self, from: Data("1e30".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int8.self, from: Data("300".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int8.self, from: Data("-129".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int16.self, from: Data("40000".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int32.self, from: Data("3000000000".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int64.self, from: Data("1e30".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt.self, from: Data("1e30".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt.self, from: Data("-1".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt8.self, from: Data("256".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt8.self, from: Data("0.5".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt16.self, from: Data("65536".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt32.self, from: Data("4294967296".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(UInt64.self, from: Data("18446744073709551616".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Int8.self, from: Data("1.0000000001".utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try Data._embeddedDecodeJSONValue(.array([.number(256)])) }
    #expect(throws: EmbeddedCodableError.self) { try Data._embeddedDecodeJSONValue(.array([.number(1.5)])) }
  }

  @Test func integerDecodersKeepInRangeValues() throws {
    #expect(try EmbeddedJSONCodec.decode(Int.self, from: Data("1.0".utf8)) == 1)
    #expect(try EmbeddedJSONCodec.decode(Int.self, from: Data("1e2".utf8)) == 100)
    #expect(try EmbeddedJSONCodec.decode(Int.self, from: Data("-0".utf8)) == 0)
    #expect(try EmbeddedJSONCodec.decode(Int8.self, from: Data("-128".utf8)) == -128)
    #expect(try EmbeddedJSONCodec.decode(Int8.self, from: Data("127".utf8)) == 127)
    #expect(try EmbeddedJSONCodec.decode(Int32.self, from: Data("2147483647".utf8)) == Int32.max)
    #expect(try EmbeddedJSONCodec.decode(Int64.self, from: Data("-9223372036854775808".utf8)) == Int64.min)
    #expect(try EmbeddedJSONCodec.decode(UInt.self, from: Data("-0".utf8)) == 0)
    #expect(try EmbeddedJSONCodec.decode(UInt8.self, from: Data("255".utf8)) == 255)
    #expect(try EmbeddedJSONCodec.decode(UInt64.self, from: Data("18446744073709549568".utf8)) == 18_446_744_073_709_549_568)
    #expect(try Data._embeddedDecodeJSONValue(.array([.number(0), .number(255)])) == Data([0, 255]))
  }

  @Test func rejectsInvalidUTF8() throws {
    let invalid: [[UInt8]] = [
      [91, 34, 0xFF, 34, 93], [91, 34, 0xC3, 34, 93], [91, 34, 0xC0, 0x80, 34, 93], [91, 34, 0xC1, 0xBF, 34, 93], [91, 34, 0xED, 0xA0, 0x80, 34, 93], [91, 34, 0xF4, 0x90, 0x80, 0x80, 34, 93],
      [91, 34, 0x80, 34, 93], [91, 34, 0xE2, 0x82, 34, 93], [91, 34, 0xF0, 0x9F, 0x98, 34, 93], [91, 34, 0xE0, 0x80, 0x80, 34, 93], [91, 34, 0xF8, 0x88, 0x80, 0x80, 0x80, 34, 93],
      [123, 34, 0xFF, 34, 58, 49, 125], [91, 34, 0xC3, 0x28, 34, 93], [91, 34, 0x61, 0xE2, 0x82], [91, 49, 93, 0xFF], [0xEF, 0xBB, 0xBF, 91, 93],
    ]
    for bytes in invalid { #expect(throws: EmbeddedCodableError.self, "\(bytes)") { try parse(bytes) } }
    #expect(try compact("[\"\u{E9}\u{20AC}\u{1F600}\"]") == "[\"\u{E9}\u{20AC}\u{1F600}\"]")
  }

  @Test func limitsNestingTo127Containers() throws {
    #expect(try compact(nested("[", "]", 127)) == nested("[", "]", 127))
    #expect(try compact(nested(#"{"a":"#, "}", 127)) == nested(#"{"a":"#, "}", 127))
    for depth in [128, 129, 1_000, 100_000] {
      #expect(throws: EmbeddedCodableError.self) { try parse(nested("[", "]", depth)) }
      #expect(throws: EmbeddedCodableError.self) { try parse(nested(#"{"a":"#, "}", depth)) }
    }
    #expect(throws: EmbeddedCodableError.self) { try parse(String(repeating: "[", count: 200_000)) }
  }

  // A value goes into the innermost container in place; a copy of the container per value made a 40,000-number array
  // take seconds instead of milliseconds.
  @Test func readsLongCollectionsInLinearTime() throws {
    let count = 200_000
    let array = "[" + (0..<count).map(String.init).joined(separator: ",") + "]"
    let object = "{" + (0..<count).map { "\"k\($0)\":\($0)" }.joined(separator: ",") + "}"
    let clock = ContinuousClock()
    let started = clock.now
    guard case .array(let values) = try parse(array) else { Issue.record("not an array"); return }
    guard case .object(let entries) = try parse(object) else { Issue.record("not an object"); return }
    #expect(values.count == count)
    #expect(entries.count == count)
    #expect(clock.now - started < .seconds(10), "200,000 values in each collection")
  }

  @Test func decodesTypedValues() throws {
    struct Row: EmbeddedCodable, Equatable {
      var id: Int, name: String, tags: [String], score: Double?
      func _embeddedJSONValue() throws -> EmbeddedJSONValue {
        .object(["id": try id._embeddedJSONValue(), "name": try name._embeddedJSONValue(), "tags": try tags._embeddedJSONValue(), "score": try score._embeddedJSONValue()])
      }
      static func _embeddedDecodeJSONValue(_ value: EmbeddedJSONValue) throws -> Row {
        guard case .object(let object) = value else { throw EmbeddedCodableError.typeMismatch }
        return Row(id: try _embeddedField(Int.self, object, "id"), name: try _embeddedField(String.self, object, "name"), tags: try _embeddedField([String].self, object, "tags"), score: try _embeddedField(Double?.self, object, "score"))
      }
    }
    let row = Row(id: 7, name: "Epis\u{F3}dio \"1\"", tags: ["a", "b"], score: nil)
    let data = try EmbeddedJSONCodec.encode(row)
    #expect(String(decoding: data, as: UTF8.self) == "{\"id\":7,\"name\":\"Epis\u{F3}dio \\\"1\\\"\",\"score\":null,\"tags\":[\"a\",\"b\"]}")
    #expect(try EmbeddedJSONCodec.decode(Row.self, from: data) == row)
    #expect(try EmbeddedJSONCodec.decode(Row.self, from: Data(#" {"tags":["a","b"],"name":"Epis\u00f3dio \"1\"","id":7e0} "#.utf8)) == row)
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Row.self, from: Data(#"{"id":7,"name":"x","tags":[],}"#.utf8)) }
    #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec.decode(Row.self, from: Data(#"{"id":"7","name":"x","tags":[]}"#.utf8)) }
  }

  @Test func refusesToEncodeNonFiniteNumbers() {
    for value in [Double.nan, .infinity, -.infinity] { #expect(throws: EmbeddedCodableError.self) { try EmbeddedJSONCodec._encode(.number(value)) } }
  }

  /// Fixtures/encode.txt holds the expected bytes of every case. About 5% of its full-precision doubles were written as a
  /// neighbouring double by an inexact float parser; for those lines the codec must write a text that reads back to the
  /// exact value instead.
  @Test func encodesTheFixtureBytes() throws {
    // The fixture is on the host's disk; `String(contentsOfFile:)` reads the framework's virtual file system.
    let fixture = String(decoding: try #require(HostFiles.read(HostFiles.directory() + "/Fixtures/encode.txt")), as: UTF8.self)
    let expected = fixture.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    let cases = EncodeCases.all()
    #expect(expected.count == cases.count)
    for (index, value) in cases.enumerated() where index < expected.count {
      let actual = String(decoding: try EmbeddedJSONCodec._encode(value), as: UTF8.self)
      if actual == expected[index] { continue }
      guard case .number(let exact) = value, case .number(let written) = try parse(expected[index]), case .number(let rewritten) = try parse(actual) else {
        Issue.record("case \(index): \(actual) != \(expected[index])")
        continue
      }
      #expect(written != exact && rewritten == exact, "case \(index): \(actual) vs \(expected[index])")
    }
  }

  @Test func encodedTextParsesBackToTheSameBytes() throws {
    for value in EncodeCases.all() {
      let data = try EmbeddedJSONCodec._encode(value)
      #expect(try EmbeddedJSONCodec._encode(try EmbeddedJSONCodec._parse(data)) == data)
    }
  }

  /// Reports the time of one decode of a large-catalog-sized payload; nothing is asserted. Run it with `-c release`.
  @Test func decodeTiming() throws {
    let payload = Data(LargeCatalogPayload.make())
    var best = Double.infinity
    for _ in 0..<15 {
      let start = ContinuousClock.now
      _ = try EmbeddedJSONCodec._parse(payload)
      let elapsed = start.duration(to: .now).components
      best = min(best, Double(elapsed.seconds) * 1e3 + Double(elapsed.attoseconds) / 1e15)
    }
    print("decode \(payload.count / 1024) KB: \(best) ms (best of 15)")
  }
}
