import Foundation
import Testing
@_spi(Renderer) @testable import SwiftUIWebTransferable

// Exercises the JSON coder paths that the rest of the suite never reaches: parser error branches, escapes, encoder and
// decoder strategies, nested and super containers, storage reuse, and the Codable forms of Date, Data and URL. Each
// expectation matches what Apple's Foundation JSONEncoder and JSONDecoder do; differences found while writing these
// tests are listed in the report instead of asserted here.

private struct StubKey: CodingKey {
  let stringValue: String
  let intValue: Int?
  init(_ string: String) {
    stringValue = string
    intValue = nil
  }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

private func encodeText<T: Encodable>(_ value: T, _ configure: (JSONEncoder) -> Void = { _ in }) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  configure(encoder)
  return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func decodeText<T: Decodable>(_ type: T.Type, _ text: String, _ configure: (JSONDecoder) -> Void = { _ in }) throws -> T {
  let decoder = JSONDecoder()
  configure(decoder)
  return try decoder.decode(type, from: Data(text.utf8))
}

private func decodingFailure<T>(_ body: () throws -> T) -> DecodingError? {
  do {
    _ = try body()
    return nil
  } catch let error as DecodingError {
    return error
  } catch {
    return nil
  }
}

private func kind(_ error: DecodingError?) -> String {
  switch error {
  case .keyNotFound?: return "keyNotFound"
  case .valueNotFound?: return "valueNotFound"
  case .typeMismatch?: return "typeMismatch"
  case .dataCorrupted?: return "dataCorrupted"
  case nil: return "none"
  default: return "other"
  }
}

// MARK: - Encodable and Decodable fixtures

private struct Pair: Codable, Equatable {
  var first: Int
}

private struct OneValue: Encodable {
  let value: Int
  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}

private struct ReadsEncoderUserInfo: Encodable {
  func encode(to encoder: any Encoder) throws {
    let key = CodingUserInfoKey(rawValue: "coverageTag")!
    var container = encoder.singleValueContainer()
    try container.encode((encoder.userInfo[key] as? String) ?? "missing")
  }
}

private struct ReadsDecoderUserInfo: Decodable, Equatable {
  let tag: String
  let value: Int
  init(from decoder: any Decoder) throws {
    let key = CodingUserInfoKey(rawValue: "coverageTag")!
    tag = (decoder.userInfo[key] as? String) ?? "missing"
    value = try decoder.singleValueContainer().decode(Int.self)
  }
}

/// Two `container(keyedBy:)` calls and two `unkeyedContainer()` calls on one encoder reuse the first storage.
private struct TwoKeyedContainers: Encodable {
  func encode(to encoder: any Encoder) throws {
    var first = encoder.container(keyedBy: StubKey.self)
    try first.encode(1, forKey: StubKey("a"))
    var second = encoder.container(keyedBy: StubKey.self)
    try second.encode(2, forKey: StubKey("b"))
  }
}

private struct TwoUnkeyedContainers: Encodable {
  func encode(to encoder: any Encoder) throws {
    var first = encoder.unkeyedContainer()
    try first.encode(1)
    var second = encoder.unkeyedContainer()
    try second.encode(2)
  }
}

private struct ExplicitNilWriter: Encodable {
  func encode(to encoder: any Encoder) throws {
    var keyed = encoder.container(keyedBy: StubKey.self)
    try keyed.encodeNil(forKey: StubKey("a"))
    try keyed.encode(1, forKey: StubKey("b"))
  }
}

private struct NestedWriter: Encodable {
  func encode(to encoder: any Encoder) throws {
    var keyed = encoder.container(keyedBy: StubKey.self)
    var nested = keyed.nestedContainer(keyedBy: StubKey.self, forKey: StubKey("n"))
    try nested.encode(1, forKey: StubKey("v"))
    var list = keyed.nestedUnkeyedContainer(forKey: StubKey("list"))
    try list.encode("a")
    var sup = keyed.superEncoder(forKey: StubKey("sup"))
    try "s".encode(to: sup)
    var superNamed = keyed.superEncoder()
    try 2.encode(to: superNamed)
  }
}

private struct UnkeyedWriter: Encodable {
  func encode(to encoder: any Encoder) throws {
    var list = encoder.unkeyedContainer()
    try list.encodeNil()
    var keyed = list.nestedContainer(keyedBy: StubKey.self)
    try keyed.encode(1, forKey: StubKey("a"))
    var inner = list.nestedUnkeyedContainer()
    try inner.encode(2)
    var sup = list.superEncoder()
    try 3.encode(to: sup)
  }
}

private struct NestedReader: Decodable, Equatable {
  let nested: Int
  let list: Int
  let sup: String
  let plain: Int
  let hasSup: Bool
  let maybeIsNil: Bool

  init(from decoder: any Decoder) throws {
    let keyed = try decoder.container(keyedBy: StubKey.self)
    let n = try keyed.nestedContainer(keyedBy: StubKey.self, forKey: StubKey("n"))
    nested = try n.decode(Int.self, forKey: StubKey("v"))
    var l = try keyed.nestedUnkeyedContainer(forKey: StubKey("list"))
    list = try l.decode(Int.self)
    sup = try keyed.superDecoder(forKey: StubKey("sup")).singleValueContainer().decode(String.self)
    plain = try keyed.superDecoder().singleValueContainer().decode(Int.self)
    hasSup = keyed.contains(StubKey("sup"))
    maybeIsNil = try keyed.decodeNil(forKey: StubKey("maybe"))
  }
}

/// Walks an unkeyed container through every entry point: `decodeNil`, `decode`, nested containers, `superDecoder`.
private struct UnkeyedReader: Decodable, Equatable {
  let count: Int?
  let firstIsNil: Bool
  let first: Int
  let secondIsNil: Bool
  let nested: Int
  let keyed: Int
  let sup: Int
  let atEnd: Bool

  init(from decoder: any Decoder) throws {
    var list = try decoder.unkeyedContainer()
    count = list.count
    firstIsNil = try list.decodeNil()
    first = try list.decode(Int.self)
    secondIsNil = try list.decodeNil()
    var inner = try list.nestedUnkeyedContainer()
    nested = try inner.decode(Int.self)
    let object = try list.nestedContainer(keyedBy: StubKey.self)
    keyed = try object.decode(Int.self, forKey: StubKey("a"))
    sup = try list.superDecoder().singleValueContainer().decode(Int.self)
    atEnd = list.isAtEnd
  }
}

private struct ReadsOne: Decodable {
  let value: Int
  init(from decoder: any Decoder) throws {
    var list = try decoder.unkeyedContainer()
    value = try list.decode(Int.self)
  }
}

private struct OptionalFields: Decodable, Equatable {
  let a: Int?
  let b: Int?
}

private struct RequiresName: Decodable {
  let name: String
}

private struct CustomKeyReader: Decodable, Equatable {
  let ab: Int
  enum CodingKeys: String, CodingKey { case ab }
}

/// Foundation's Data form: an unkeyed list of bytes, read and written through `Data`'s own Codable conformance.
private struct DataWrapper: Codable, Equatable {
  let data: Data
  init(data: Data) { self.data = data }
  init(from decoder: any Decoder) throws { data = try Data(from: decoder) }
  func encode(to encoder: any Encoder) throws { try data.encode(to: encoder) }
}

/// URL's archived form, read and written through `URL`'s own Codable conformance.
private struct URLWrapper: Codable {
  let url: URL
  init(url: URL) { self.url = url }
  init(from decoder: any Decoder) throws { url = try URL(from: decoder) }
  func encode(to encoder: any Encoder) throws { try url.encode(to: encoder) }
}

private struct RelativeURLInput: Encodable {
  let relative: String
  let base: String?
}

@Suite
struct JSONCodingCoverageTests {
  // MARK: Parser

  @Test
  func decodesEscapedUnicodeIncludingSurrogatePairs() throws {
    #expect(try decodeText(String.self, #""é😀""#) == "é😀")
    #expect(try decodeText(String.self, #""é\b\f\n\r\t\/\\\"""#) == "é\u{08}\u{0C}\n\r\t/\\\"")
    #expect(try decodeText(String.self, #""é""#) == "é")
  }

  @Test
  func rejectsLoneOrBrokenSurrogatesAndBadUnicodeEscapes() {
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""\ud83d""#) }
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""\ud83dx""#) }
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""\ud83dA""#) }
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""\u12""#) }
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""\u12G4""#) }
  }

  @Test
  func rejectsInvalidEscapesControlCharactersAndUnterminatedStrings() {
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""\x""#) }
    #expect(throws: DecodingError.self) { try decodeText(String.self, "\"a\u{01}b\"") }
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""abc"#) }
    #expect(throws: DecodingError.self) { try decodeText(String.self, #""ab\"#) }
  }

  @Test
  func acceptsExponentSignsInNumbers() throws {
    #expect(try decodeText(Double.self, "1.5E+3") == 1500)
    #expect(try decodeText(Double.self, "2e-2") == 0.02)
    #expect(try decodeText(Double.self, "-0.25e1") == -2.5)
  }

  @Test
  func rejectsMalformedNumbersAndTrailingContent() {
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "01") }
    #expect(throws: DecodingError.self) { try decodeText(Double.self, "1.") }
    #expect(throws: DecodingError.self) { try decodeText(Double.self, "1e") }
    #expect(throws: DecodingError.self) { try decodeText(Double.self, "1e+") }
    #expect(throws: DecodingError.self) { try decodeText(Double.self, "-") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "1 2") }
  }

  @Test
  func rejectsMalformedContainersLiteralsAndEmptyInput() {
    #expect(throws: DecodingError.self) { try decodeText([Int].self, "[1 2]") }
    #expect(throws: DecodingError.self) { try decodeText([Int].self, "[1,") }
    #expect(throws: DecodingError.self) { try decodeText([String: Int].self, #"{"a" 1}"#) }
    #expect(throws: DecodingError.self) { try decodeText([String: Int].self, "{1:2}") }
    #expect(throws: DecodingError.self) { try decodeText(Bool.self, "tru") }
    #expect(throws: DecodingError.self) { try decodeText(Bool.self, "nul") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "x") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "") }
  }

  @Test
  func decodesArraysAndObjectsWithWhitespace() throws {
    #expect(try decodeText([Int].self, "[ 1 , 2 ]") == [1, 2])
    #expect(try decodeText([String: Int].self, #"{ "a" : 1 , "b" : 2 }"#) == ["a": 1, "b": 2])
  }

  // MARK: Integer and float decoding

  @Test
  func decodesIntegersExactlyAndWholeNumbersFromFloatingText() throws {
    #expect(try decodeText(Int64.self, "9223372036854775807") == Int64.max)
    #expect(try decodeText(UInt64.self, "18446744073709551615") == UInt64.max)
    #expect(try decodeText(Int.self, "1e2") == 100)
    #expect(try decodeText(Int.self, "1.0") == 1)
  }

  @Test
  func rejectsIntegersThatDoNotFit() {
    #expect(kind(decodingFailure { try decodeText(Int8.self, "300") }) == "dataCorrupted")
    #expect(kind(decodingFailure { try decodeText(Int.self, "1.5") }) == "dataCorrupted")
  }

  @Test
  func decodesNonFiniteDoublesOnlyWhenConfigured() throws {
    let values = try decodeText([Double].self, #"["Infinity","-Infinity","NaN"]"#) {
      $0.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    }
    #expect(values.count == 3)
    #expect(values[0] == .infinity)
    #expect(values[1] == -.infinity)
    #expect(values[2].isNaN)
    #expect(kind(decodingFailure { try decodeText(Double.self, #""Infinity""#) }) == "typeMismatch")
    #expect(kind(decodingFailure { try decodeText(Double.self, #""x""#) }) == "typeMismatch")
  }

  @Test
  func encodesNonFiniteDoublesOnlyWhenConfigured() throws {
    #expect(throws: EncodingError.self) { try encodeText(Double.nan) }
    #expect(throws: EncodingError.self) { try encodeText(Double.infinity) }
    let text = try encodeText([Double.infinity, -Double.infinity, Double.nan]) {
      $0.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "NaN")
    }
    #expect(text == #"["+inf","-inf","NaN"]"#)
  }

  // MARK: Writer escaping

  @Test
  func escapesControlCharactersLikeFoundation() throws {
    #expect(try encodeText("a\u{01}\u{1f}\u{08}\u{0C}b") == #""a\u0001\u001f\b\fb""#)
  }

  @Test
  func writesPrettyPrintedObjectsWithoutEscapingSlashesWhenAsked() throws {
    let text = try encodeText(Pair(first: 3)) { $0.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes] }
    #expect(text == "{\n  \"first\" : 3\n}")
    #expect(try encodeText("https://a.b/c") { $0.outputFormatting = [.withoutEscapingSlashes] } == #""https://a.b/c""#)
  }

  // MARK: Date strategies

  @Test
  func customDateEncodingStrategyWritesTheClosureOutput() throws {
    let text = try encodeText([Date(timeIntervalSince1970: 5)]) {
      $0.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode("custom-\(Int(date.timeIntervalSince1970))")
      }
    }
    #expect(text == #"["custom-5"]"#)
  }

  @Test
  func customDateDecodingStrategyReadsTheClosureValue() throws {
    let date = try decodeText(Date.self, "4") {
      $0.dateDecodingStrategy = .custom { decoder in
        Date(timeIntervalSince1970: try decoder.singleValueContainer().decode(Double.self) * 10)
      }
    }
    #expect(date == Date(timeIntervalSince1970: 40))
  }

  @Test
  func millisecondsAndSecondsDecodingStrategiesScaleTheNumber() throws {
    #expect(try decodeText(Date.self, "1500") { $0.dateDecodingStrategy = .millisecondsSince1970 } == Date(timeIntervalSince1970: 1.5))
    #expect(try decodeText(Date.self, "2") { $0.dateDecodingStrategy = .secondsSince1970 } == Date(timeIntervalSince1970: 2))
  }

  @Test
  func iso8601EncodingWritesDatesBeforeTheEpoch() throws {
    #expect(try encodeText(Date(timeIntervalSince1970: -1)) { $0.dateEncodingStrategy = .iso8601 } == #""1969-12-31T23:59:59Z""#)
  }

  @Test
  func iso8601DecodingReadsOffsetsAndFractionalSeconds() throws {
    let iso = { (text: String) in try decodeText(Date.self, text) { $0.dateDecodingStrategy = .iso8601 } }
    #expect(try iso(#""2023-11-14T22:13:20+02:00""#) == Date(timeIntervalSince1970: 1_699_992_800))
    #expect(try iso(#""2023-11-14T22:13:20+0200""#) == Date(timeIntervalSince1970: 1_699_992_800))
    #expect(try iso(#""2023-11-14T22:13:20-05:30""#) == Date(timeIntervalSince1970: 1_700_019_800))
    #expect(try iso(#""2023-11-14T22:13:20.5Z""#) == Date(timeIntervalSince1970: 1_700_000_000.5))
  }

  @Test
  func iso8601DecodingRejectsMalformedStrings() {
    let iso = { (text: String) in decodingFailure { try decodeText(Date.self, text) { $0.dateDecodingStrategy = .iso8601 } } }
    #expect(kind(iso(#""not-a-date""#)) == "dataCorrupted")
    #expect(kind(iso(#""2023-11-14""#)) == "dataCorrupted")
    #expect(kind(iso(#""2023-11-14T22:13:20.Z""#)) == "dataCorrupted")
    #expect(kind(iso(#""2023-11-14T22:13:20+02:""#)) == "dataCorrupted")
    #expect(kind(iso("1700000000")) == "typeMismatch")
  }

  // MARK: Data strategies

  @Test
  func deferredToDataEncodesAndDecodesAByteList() throws {
    #expect(try encodeText(Data([1, 2])) { $0.dataEncodingStrategy = .deferredToData } == "[1,2]")
    #expect(try decodeText(Data.self, "[1,2]") { $0.dataDecodingStrategy = .deferredToData } == Data([1, 2]))
  }

  @Test
  func customDataStrategiesRunTheirClosures() throws {
    let encoded = try encodeText(Data([1, 2, 3])) {
      $0.dataEncodingStrategy = .custom { data, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(data.count)
      }
    }
    #expect(encoded == "3")
    let decoded = try decodeText(Data.self, #""hi""#) {
      $0.dataDecodingStrategy = .custom { decoder in Data(try decoder.singleValueContainer().decode(String.self).utf8) }
    }
    #expect(decoded == Data("hi".utf8))
  }

  @Test
  func base64DecodingRejectsInvalidText() {
    #expect(kind(decodingFailure { try decodeText(Data.self, #""!!!""#) }) == "dataCorrupted")
  }

  // MARK: Key strategies

  @Test
  func customKeyEncodingStrategyTransformsEachKey() throws {
    let text = try encodeText(Pair(first: 1)) {
      $0.keyEncodingStrategy = .custom { path in StubKey(path.last!.stringValue.uppercased()) }
    }
    #expect(text == #"{"FIRST":1}"#)
  }

  @Test
  func customKeyDecodingStrategyTransformsEachKey() throws {
    let value = try decodeText(CustomKeyReader.self, #"{"Ab":1}"#) {
      $0.keyDecodingStrategy = .custom { path in StubKey(path.last!.stringValue.lowercased()) }
    }
    #expect(value.ab == 1)
  }

  // MARK: Encoder containers

  @Test
  func repeatedContainerRequestsShareOneStorage() throws {
    #expect(try encodeText(TwoKeyedContainers()) == #"{"a":1,"b":2}"#)
    #expect(try encodeText(TwoUnkeyedContainers()) == "[1,2]")
  }

  @Test
  func explicitNilForKeyWritesNull() throws {
    #expect(try encodeText(ExplicitNilWriter()) == #"{"a":null,"b":1}"#)
  }

  @Test
  func nestedAndSuperContainersEncodeInPlace() throws {
    #expect(try encodeText(NestedWriter()) == #"{"list":["a"],"n":{"v":1},"sup":"s","super":2}"#)
  }

  @Test
  func unkeyedContainersEncodeNilNestedAndSuper() throws {
    #expect(try encodeText(UnkeyedWriter()) == #"[null,{"a":1},[2],3]"#)
  }

  @Test
  func encoderUserInfoReachesTheEncodingType() throws {
    let encoder = JSONEncoder()
    encoder.userInfo = [CodingUserInfoKey(rawValue: "coverageTag")!: "from-encoder"]
    #expect(String(decoding: try encoder.encode(ReadsEncoderUserInfo()), as: UTF8.self) == #""from-encoder""#)
    #expect(try encodeText(ReadsEncoderUserInfo()) == #""missing""#)
  }

  // MARK: Decoder containers

  @Test
  func decoderUserInfoReachesTheDecodingType() throws {
    let decoder = JSONDecoder()
    decoder.userInfo = [CodingUserInfoKey(rawValue: "coverageTag")!: "from-decoder"]
    let value = try decoder.decode(ReadsDecoderUserInfo.self, from: Data("7".utf8))
    #expect(value.tag == "from-decoder")
    #expect(value.value == 7)
  }

  @Test
  func keyedContainerReadsNestedSuperAndNilMembers() throws {
    let value = try decodeText(NestedReader.self, #"{"list":[7],"maybe":null,"n":{"v":1},"sup":"s","super":2}"#)
    #expect(value.nested == 1)
    #expect(value.list == 7)
    #expect(value.sup == "s")
    #expect(value.plain == 2)
    #expect(value.hasSup)
    #expect(value.maybeIsNil)
  }

  @Test
  func unkeyedContainerReadsEveryEntryPoint() throws {
    let value = try decodeText(UnkeyedReader.self, #"[1,null,[2],{"a":3},4]"#)
    #expect(value.count == 5)
    #expect(value.firstIsNil == false)
    #expect(value.first == 1)
    #expect(value.secondIsNil)
    #expect(value.nested == 2)
    #expect(value.keyed == 3)
    #expect(value.sup == 4)
    #expect(value.atEnd)
  }

  @Test
  func unkeyedContainerPastTheEndThrowsValueNotFound() {
    #expect(kind(decodingFailure { try decodeText(ReadsOne.self, "[]") }) == "valueNotFound")
  }

  @Test
  func optionalMembersDecodeFromNullAbsentAndPresentValues() throws {
    #expect(try decodeText(OptionalFields.self, #"{"a":null,"b":2}"#) == OptionalFields(a: nil, b: 2))
    #expect(try decodeText(OptionalFields.self, #"{"b":2}"#) == OptionalFields(a: nil, b: 2))
    #expect(try decodeText(OptionalFields.self, #"{"a":1,"b":null}"#) == OptionalFields(a: 1, b: nil))
  }

  @Test
  func missingRequiredKeyThrowsKeyNotFound() {
    #expect(kind(decodingFailure { try decodeText(RequiresName.self, "{}") }) == "keyNotFound")
  }

  @Test
  func nullForANonOptionalBuiltInThrowsValueNotFound() {
    #expect(kind(decodingFailure { try decodeText(Int.self, "null") }) == "valueNotFound")
    #expect(kind(decodingFailure { try decodeText(String.self, "null") }) == "valueNotFound")
    #expect(kind(decodingFailure { try decodeText(Date.self, "null") }) == "valueNotFound")
  }

  @Test
  func containerKindMismatchesThrowTypeMismatch() {
    #expect(kind(decodingFailure { try decodeText(String.self, "1") }) == "typeMismatch")
    #expect(kind(decodingFailure { try decodeText(Bool.self, "1") }) == "typeMismatch")
    #expect(kind(decodingFailure { try decodeText(Pair.self, "[1]") }) == "typeMismatch")
    #expect(kind(decodingFailure { try decodeText([Int].self, #"{"a":1}"#) }) == "typeMismatch")
  }

  // MARK: Date, Data and URL Codable forms

  @Test
  func dataCodableFormIsAnUnkeyedByteList() throws {
    #expect(try encodeText(DataWrapper(data: Data([1, 2]))) == "[1,2]")
    #expect(try decodeText(DataWrapper.self, "[1,2]") == DataWrapper(data: Data([1, 2])))
  }

  @Test
  func urlCodableArchivesTheRelativeStringAndResolvesAgainstBase() throws {
    do {
      let text = try encodeText(URLWrapper(url: URL(string: "https://example.com/a")!))
      #expect(text == #"{"relative":"https:\/\/example.com\/a"}"#)
    } catch {
      Issue.record("URL encoding threw \(error)")
    }
    let resolved = { (text: String) in try decodeText(URLWrapper.self, text).url.absoluteString }
    #expect(try resolved(#"{"relative":"https://other.org/z","base":"https://a.b/x/y"}"#) == "https://other.org/z")
    #expect(try resolved(#"{"relative":"/z","base":"https://a.b/x/y"}"#) == "https://a.b/z")
    #expect(try resolved(#"{"relative":"c","base":"https://a.b/x/y"}"#) == "https://a.b/x/c")
    #expect(try resolved(#"{"relative":"/z","base":"mailto:me"}"#) == "/z")
    #expect(try resolved(#"{"relative":"c","base":"mailto:me"}"#) == "c")
    #expect(try resolved(#"{"relative":"c"}"#) == "c")
  }

  @Test
  func urlCodableRejectsAnEmptyOrInvalidString() {
    #expect(kind(decodingFailure { try decodeText(URLWrapper.self, #"{"relative":""}"#) }) == "dataCorrupted")
    #expect(kind(decodingFailure { try decodeText(URLWrapper.self, #"{"relative":"1http://x"}"#) }) == "dataCorrupted")
  }

  @Test
  func urlDecodesFromJSONStringsAndRejectsInvalidOnes() throws {
    #expect(try decodeText(URL.self, #""https://example.com/a""#) == URL(string: "https://example.com/a")!)
    #expect(kind(decodingFailure { try decodeText(URL.self, #""""#) }) == "dataCorrupted")
  }

  // MARK: Date runtime

  @Test
  func installedClockDrivesDateNowAndRestoresTheHostClock() {
    SwiftUIWebDateRuntime.install(now: { 42 })
    defer { SwiftUIWebDateRuntime.install(now: nil) }
    #expect(Date().timeIntervalSince1970 == 42)
    #expect(Date.now.timeIntervalSince1970 == 42)
  }

  @Test
  func addTimeIntervalMovesTheDateInPlace() {
    var date = Date(timeIntervalSince1970: 1)
    date.addTimeInterval(2.5)
    #expect(date == Date(timeIntervalSince1970: 3.5))
  }

  // MARK: Foundation parity found in review

  private struct Profile: Codable, Equatable {
    let displayName: String
    let scores: [String: Int]
  }

  @Test
  func keyStrategiesLeaveStringKeyedDictionaryKeysAlone() throws {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = .sortedKeys
    let dictionary = ["userID": 1, "user_id": 2]
    let text = String(decoding: try encoder.encode(dictionary), as: UTF8.self)
    #expect(text == #"{"userID":1,"user_id":2}"#)

    let profile = Profile(displayName: "Ana", scores: ["firstRound": 3])
    let encoded = String(decoding: try encoder.encode(profile), as: UTF8.self)
    #expect(encoded == #"{"display_name":"Ana","scores":{"firstRound":3}}"#)

    let decoded = try decodeText(Profile.self, #"{"display_name":"Ana","scores":{"first_round":3}}"#) {
      $0.keyDecodingStrategy = .convertFromSnakeCase
    }
    #expect(decoded == Profile(displayName: "Ana", scores: ["first_round": 3]))
    #expect(throws: DecodingError.self) { try decodeText([String: Int].self, "[1]") }
  }

  @Test
  func integersWrittenWithAFractionOrExponentKeepEveryDigit() throws {
    #expect(try decodeText(Int64.self, "9007199254740993.0") == 9_007_199_254_740_993)
    #expect(try decodeText(Int64.self, "-9223372036854775808.000") == Int64.min)
    #expect(try decodeText(UInt64.self, "1.8446744073709551615e19") == UInt64.max)
    #expect(try decodeText(Int.self, "12e2") == 1200)
    #expect(try decodeText(Int.self, "1200e-2") == 12)
    #expect(try decodeText(Int.self, "0.0e5") == 0)
    #expect(try decodeText(Int.self, "-0.0") == 0)
    #expect(try decodeText(Int.self, "0e-5") == 0)
    #expect(try decodeText(Int.self, "3.00") == 3)
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "1.5") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "15e-1") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "1e-5") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "1e99999") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "1e-9223372036854775808") }
    #expect(throws: DecodingError.self) { try decodeText(Int.self, "1e9223372036854775807") }
    #expect(throws: DecodingError.self) { try decodeText(Int8.self, "1.28e2") }
    #expect(throws: DecodingError.self) { try decodeText(Int64.self, "1e400") }
  }

  @Test
  func numbersPastTheFloatingPointRangeAreRejected() throws {
    #expect(throws: DecodingError.self) { try decodeText(Double.self, "1e400") }
    #expect(throws: DecodingError.self) { try decodeText(Double.self, "-1e400") }
    #expect(throws: DecodingError.self) { try decodeText(Float.self, "1e40") }
    #expect(try decodeText(Double.self, "1e300") == 1e300)
    #expect(try decodeText(Float.self, "3.5") == 3.5)
  }
  @Test
  func valuesOfTheWrongKindAreRejectedForURLsAndDates() {
    #expect(throws: DecodingError.self) { try decodeText(URL.self, "1") }
    #expect(throws: DecodingError.self) { try decodeText(Date.self, "1") { $0.dateDecodingStrategy = .iso8601 } }
  }

  @Test
  func nanDecodesFromItsConfiguredString() throws {
    let value = try decodeText(Double.self, #""not-a-number""#) {
      $0.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "not-a-number")
    }
    #expect(value.isNaN)
  }

  private struct ListedKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
  }

  private struct ListedKeys: Decodable {
    let keys: [String]
    init(from decoder: any Decoder) throws {
      keys = try decoder.container(keyedBy: ListedKey.self).allKeys.map(\.stringValue).sorted()
    }
  }

  @Test
  func aKeyedContainerListsTheKeysOfItsObject() throws {
    #expect(try decodeText(ListedKeys.self, #"{"b":1,"a":2}"#).keys == ["a", "b"])
  }
  // MARK: Encoding of every width, empty containers and escapes

  @Test
  func encodesEveryIntegerWidthFloatsEmptyContainersAndEscapes() throws {
    let encoder = JSONEncoder()
    func text<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
    #expect(try text(Int8(-8)) == "-8")
    #expect(try text(Int16(-16)) == "-16")
    #expect(try text(Int32(-32)) == "-32")
    #expect(try text(UInt(7)) == "7")
    #expect(try text(UInt16(16)) == "16")
    #expect(try text(UInt32(32)) == "32")
    #expect(try text(UInt64(64)) == "64")
    #expect(try text(Float(1.5)) == "1.5")
    #expect(try text([Int]()) == "[]")
    #expect(try text([String: Int]()) == "{}")
    #expect(try text("a\"b\\c\nd\re\tf") == #""a\"b\\c\nd\re\tf""#)
    encoder.dateEncodingStrategy = .secondsSince1970
    #expect(try text(Date(timeIntervalSince1970: 3)).hasPrefix("3"))
  }
}
