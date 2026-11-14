import Foundation
import Testing
import SwiftUIWeb
@testable import Foundation

@Suite(.processGlobalState)
@MainActor
final class WebFoundationTests {
  @Test
  func measurementPreferencesFollowTheLocaleRegion() {
    // Checked against Foundation's MeasurementFormatter (unitOptions empty) for these regions.
    _expectEqual(_MeasurementPreferences.effectiveRegion("us", language: "en"), "US")
    _expectEqual(_MeasurementPreferences.effectiveRegion(nil, language: "en"), "US")
    _expectEqual(_MeasurementPreferences.effectiveRegion(nil, language: "pt"), "")
    _expectEqual(_MeasurementPreferences.effectiveRegion("BR", language: "pt"), "BR")

    _expectEqual(_MeasurementPreferences.massIdentifiers(region: "US"), ["pound"])
    _expectEqual(_MeasurementPreferences.massIdentifiers(region: "BR"), ["kilogram"])
    _expectEqual(_MeasurementPreferences.massIdentifiers(region: "LR"), ["kilogram"])
    _expectEqual(_MeasurementPreferences.massIdentifiers(region: "MM"), ["kilogram"])
    _expectEqual(_MeasurementPreferences.massIdentifiers(region: "GB"), ["kilogram", "gram", "pound", "ounce", "stone", "metric-ton"])

    _expectEqual(_MeasurementPreferences.lengthIdentifiers(region: "US"), ["mile"])
    _expectEqual(_MeasurementPreferences.lengthIdentifiers(region: "GB"), ["mile"])
    _expectEqual(_MeasurementPreferences.lengthIdentifiers(region: "CA"), ["kilometer"])
    _expectEqual(_MeasurementPreferences.lengthIdentifiers(region: "SE"), ["kilometer"])

    _expectEqual(_MeasurementPreferences.temperatureIdentifiers(region: "US"), ["fahrenheit"])
    _expectEqual(_MeasurementPreferences.temperatureIdentifiers(region: "PR"), ["fahrenheit"])
    _expectEqual(_MeasurementPreferences.temperatureIdentifiers(region: "GB"), ["celsius"])
    _expectEqual(_MeasurementPreferences.temperatureIdentifiers(region: "LR"), ["celsius"])

    _expectEqual(_MeasurementPreferences.hasIntlName("kilogram"), true)
    _expectEqual(_MeasurementPreferences.hasIntlName("fahrenheit"), true)
    _expectEqual(_MeasurementPreferences.hasIntlName("kelvin"), false)
    _expectEqual(_MeasurementPreferences.hasIntlName("milligram"), false)
    _expectEqual(_MeasurementPreferences.hasIntlName("metric-ton"), false)
  }

  @Test
  func stringComponentsByStringPreserveFoundationSplittingSemantics() {
    _expectEqual(WebStringComponents.split("a::b::::c", separatedBy: "::"), ["a", "b", "", "c"])
    _expectEqual(WebStringComponents.split("::a::", separatedBy: "::"), ["", "a", ""])
    _expectEqual(WebStringComponents.split("sem separador", separatedBy: ","), ["sem separador"])
    _expectEqual(WebStringComponents.split("🙂|café|🌱", separatedBy: "|"), ["🙂", "café", "🌱"])
    _expectEqual(WebStringComponents.split("abc", separatedBy: ""), ["abc"])
    _expectEqual("a::b".components(separatedBy: "::"), ["a", "b"])
  }

  @Test
  func stringComponentsByCharacterSetPreserveEmptySegments() {
    _expectEqual(WebStringComponents.split("a  b\nc", where: { $0 == " " || $0 == "\n" }), ["a", "", "b", "c"])
    _expectEqual("a  b".components(separatedBy: CharacterSet.whitespacesAndNewlines), ["a", "", "b"])
  }

  @Test
  func jsonValueRoundTripsEveryNativeCaseAndNestedPayload() throws {
    let value: JSONValue = .object([
      "string": .string("olá"),
      "number": .number(42.5),
      "bool": .bool(true),
      "array": .array([.null, .string("nested")]),
      "object": .object(["answer": .number(6)])
    ])

    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    _expectEqual(decoded, value)

    // A top-level array takes the explicit array decoding path in JSONValue
    // (nested arrays are decoded by Codable's collection machinery instead).
    let topLevelArray = try JSONDecoder().decode(JSONValue.self, from: Data("[null,\"nested\"]".utf8))
    _expectEqual(topLevelArray, .array([.null, .string("nested")]))
  }

  @Test
  func jsonValueRejectsADecoderThatCannotRepresentAnyJSONCase() {
    _expectThrows(try JSONValue(from: UnsupportedJSONDecoder()))
  }

  @Test
  func jsonValueAccessorsDistinguishCasesAndDictionaryHelpersHaveFallbacks() {
    let object: [String: JSONValue] = [
      "title": .string("Title"),
      "count": .number(7.9),
      "items": .array([
        .object(["title": .string("first")]),
        .bool(false),
        .object(["title": .string("second")])
      ]),
      "null": .null
    ]

    _expectEqual(object["title"]?.stringValue, "Title")
    _expectEqual(object["count"]?.intValue, 7)
    _expectNil(object["null"]?.stringValue)
    _expectNil(object["title"]?.intValue)
    _expectEqual(object.text("title"), "Title")
    _expectEqual(object.text("missing", fallback: "fallback"), "fallback")
    _expectEqual(object.integer("count"), 7)
    _expectEqual(object.integer("missing", fallback: 9), 9)
    _expectEqual(object.values("items").count, 2)
    _expectEqual(object.values("missing").count, 0)
    _expectEqual(JSONValue.bool(false).stringValue, nil)
  }

  @Test
  func webEnvironmentProviderCanBeInstalledAndResetWithoutLeakingState() {
    // Exercise the zero-cost default provider before installing a host adapter.
    _expectNil(WebEnvironment.value(forKey: "DEFAULT"))
    WebEnvironment.install(provider: nil)
    _expectEqual(WebEnvironment.value(forKey: "missing"), nil)
    WebEnvironment.install { key in
      key == "API_HOST" ? "https://example.test" : nil
    }
    _expectEqual(WebEnvironment.value(forKey: "API_HOST"), "https://example.test")
    _expectNil(WebEnvironment.value(forKey: "MISSING"))

    WebEnvironment.install(provider: nil)
    _expectNil(WebEnvironment.value(forKey: "API_HOST"))
  }

  @Test
  func numberValuesBridgeIntegersDoublesAndBooleans() {
    _expectEqual(Foundation.NSNumber(value: 42).doubleValue, 42)
    _expectEqual(Foundation.NSNumber(value: 7.9).intValue, 7)
    _expectEqual(Foundation.NSNumber(value: -7.9).intValue, -7)
    _expectEqual(Foundation.NSNumber(value: true).intValue, 1)
    _expectEqual(Foundation.NSNumber(value: false).doubleValue, 0)
  }

  @Test
  func numberFormatterWithoutAStyleRoundsToAnUngroupedInteger() {
    let formatter = Foundation.NumberFormatter()
    _expectEqual(formatter.numberStyle, Foundation.NumberFormatter.Style.none)
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 1234.6)), "1235")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: -2.5)), "-3")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 0)), "0")
  }

  @Test
  func numberFormatterDecimalStyleGroupsThousandsAndTrimsTrailingZeros() {
    let formatter = Foundation.NumberFormatter()
    formatter.numberStyle = .decimal
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 1_234_567.891)), "1,234,567.891")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 42)), "42")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 0.05)), "0.05")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 999)), "999")

    formatter.maximumFractionDigits = 2
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: -1234.5678)), "-1,234.57")

    formatter.minimumFractionDigits = 2
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 3.1)), "3.10")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 3)), "3.00")

    formatter.minimumFractionDigits = 0
    formatter.groupingSeparator = "."
    formatter.decimalSeparator = ","
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 1234.5)), "1.234,5")
  }

  @Test
  func numberFormatterPercentStyleScalesBeforeFormatting() {
    let formatter = Foundation.NumberFormatter()
    formatter.numberStyle = .percent
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 0.256)), "25.6%")
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: 12.5)), "1,250%")
    formatter.maximumFractionDigits = 0
    _expectEqual(formatter.string(from: Foundation.NSNumber(value: -0.125)), "-13%")
  }
}

private struct UnsupportedJSONDecoder: Decoder {
  var codingPath: [any CodingKey] { [] }
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
    throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: codingPath, debugDescription: "unsupported"))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: codingPath, debugDescription: "unsupported"))
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    UnsupportedSingleValueContainer(codingPath: codingPath)
  }
}

private struct UnsupportedSingleValueContainer: SingleValueDecodingContainer {
  let codingPath: [any CodingKey]

  func decodeNil() -> Bool { false }

  func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
    throw DecodingError.typeMismatch(type, .init(codingPath: codingPath, debugDescription: "unsupported"))
  }
}

// The browser stand-in for Foundation's streams is written against these observed behaviors of the real Foundation;
// the Embedded lowering app prints the same facts and the browser runtime test compares them.
@Suite
struct FoundationStreamReferenceTests {
  @Test
  func memoryStreamsReportStatusesAndEndOfInput() {
    let input = InputStream(data: Data("abcde".utf8))
    var chunk = [UInt8](repeating: 0, count: 3)
    #expect(input.streamStatus == .notOpen)
    #expect(input.read(&chunk, maxLength: 3) == -1)
    input.open()
    #expect(input.hasBytesAvailable)
    #expect(input.read(&chunk, maxLength: 3) == 3 && input.streamStatus == .open)
    #expect(input.read(&chunk, maxLength: 3) == 2 && input.streamStatus == .atEnd && !input.hasBytesAvailable)
    #expect(input.read(&chunk, maxLength: 3) == 0)
  }

  @Test
  func typedContainersSerializeAndValidate() throws {
    func text(_ value: Any) throws -> String {
      String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }
    let optionalFields: [String: Any?] = ["a": 1, "b": nil]
    #expect(try text(["a": 1]) == #"{"a":1}"#)
    #expect(try text(["a": 1.5, "b": 2.0]) == #"{"a":1.5,"b":2}"#)
    #expect(try text([["a": "x"]]) == #"[{"a":"x"}]"#)
    #expect(try text(optionalFields) == #"{"a":1,"b":null}"#)
    #expect(!JSONSerialization.isValidJSONObject(["a": Double.nan]))
    #expect(!JSONSerialization.isValidJSONObject([1: 2]))
  }

  @Test
  func jsonStreamsRoundTripAndBufferStreamsTakeWholeWritesOnly() throws {
    let output = OutputStream(toMemory: ())
    output.open()
    var failure: NSError?
    let count = JSONSerialization.writeJSONObject(["a": [1, 2]], to: output, options: [.sortedKeys], error: &failure)
    #expect(count == 11 && failure == nil)
    let property = output.property(forKey: .dataWrittenToMemoryStreamKey)
    guard let written = property as? Data else { Issue.record("no data written"); return }
    let input = InputStream(data: written)
    input.open()
    let parsed = try JSONSerialization.jsonObject(with: input)
    guard let object = parsed as? [String: Any] else { Issue.record("not an object"); return }
    #expect((object["a"] as? [Int]) == [1, 2])
    #expect(input.streamStatus == .atEnd)

    let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
    defer { storage.deallocate() }
    let bounded = OutputStream(toBuffer: storage, capacity: 4)
    bounded.open()
    let overflow = JSONSerialization.writeJSONObject(["abc": 1], to: bounded, options: [], error: &failure)
    #expect(overflow == -1 && failure?.domain == NSCocoaErrorDomain && failure?.code == 512)
    #expect(bounded.streamStatus == .error && !bounded.hasSpaceAvailable)
  }
}
