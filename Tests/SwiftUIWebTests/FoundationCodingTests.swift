import Foundation
import Testing
@testable import SwiftUIWeb

// SwiftUIWeb's coders write and read JSON in Foundation's forms (strategies, number text, escaping, pretty layout,
// archive shapes), so an archive made on an Apple platform opens here and the reverse.
/// Decodes any JSON value without keeping it, so a test can parse a deeply nested document.
private struct JSONNestingProbe: Decodable {
  init(from decoder: Decoder) throws {}
}

@Suite
struct FoundationCodingTests {
  private struct Profile: Codable, Equatable {
    var userName: String
    var createdAt: Date
    var avatar: Data
    var homePage: URL
    var score: Double
    var visits: Int64
  }

  private func json<T: Encodable>(_ value: T, _ configure: (JSONEncoder) -> Void = { _ in }) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    configure(encoder)
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  @Test
  func defaultStrategiesMatchFoundation() throws {
    let profile = Profile(
      userName: "ana", createdAt: Date(timeIntervalSinceReferenceDate: 10), avatar: Data([1, 2, 3]),
      homePage: URL(string: "https://example.com/a")!, score: 1.5, visits: 9_007_199_254_740_993
    )
    // Dates as seconds since 2001, data as base64, URLs as strings, `/` escaped, integers exact past 2^53.
    let text = try json(profile)
    #expect(text == #"{"avatar":"AQID","createdAt":10,"homePage":"https:\/\/example.com\/a","score":1.5,"userName":"ana","visits":9007199254740993}"#)
    #expect(try JSONDecoder().decode(Profile.self, from: Data(text.utf8)) == profile)
  }

  @Test
  func strategiesAndFormattingMatchFoundation() throws {
    struct Event: Codable { var startDate: Date; var homePage: URL }
    let event = Event(startDate: Date(timeIntervalSince1970: 1_700_000_000), homePage: URL(string: "https://a.b/c")!)
    let text = try json(event) {
      $0.keyEncodingStrategy = .convertToSnakeCase
      $0.dateEncodingStrategy = .iso8601
      $0.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    }
    #expect(text == "{\n  \"home_page\" : \"https://a.b/c\",\n  \"start_date\" : \"2023-11-14T22:13:20Z\"\n}")

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Event.self, from: Data(text.utf8))
    #expect(decoded.startDate == event.startDate && decoded.homePage == event.homePage)
    #expect(try json([Date(timeIntervalSince1970: 2)]) { $0.dateEncodingStrategy = .millisecondsSince1970 } == "[2000]")
  }

  @Test
  func keyCaseConversionMatchesFoundation() {
    #expect(_EmbeddedKeyCase.snakeFromCamel("myURLProperty") == "my_url_property")
    #expect(_EmbeddedKeyCase.camelFromSnake("my_url_property") == "myUrlProperty")
    #expect(_EmbeddedKeyCase.camelFromSnake("_leading_and_trailing_") == "_leadingAndTrailing_")
    #expect(_EmbeddedKeyCase.camelFromSnake("single") == "single")
  }

  @Test
  func keyCaseConversionCapitalizesDigitWordsLikeFoundation() {
    // Open-Meteo's keys: a word that starts with a digit is capitalized at its first letter (`2m` -> `2M`).
    #expect(_EmbeddedKeyCase.camelFromSnake("temperature_2m") == "temperature2M")
    #expect(_EmbeddedKeyCase.camelFromSnake("temperature_2m_max") == "temperature2MMax")
    #expect(_EmbeddedKeyCase.camelFromSnake("wind_speed_10m") == "windSpeed10M")
    #expect(_EmbeddedKeyCase.camelFromSnake("uv_index_max") == "uvIndexMax")
    #expect(_EmbeddedKeyCase.camelFromSnake("is_day") == "isDay")
    #expect(_EmbeddedKeyCase.camelFromSnake("pressure_msl") == "pressureMsl")
    // Leading and trailing underscores are kept; empty words between them are dropped.
    #expect(_EmbeddedKeyCase.camelFromSnake("_leading") == "_leading")
    #expect(_EmbeddedKeyCase.camelFromSnake("trailing_") == "trailing_")
    #expect(_EmbeddedKeyCase.camelFromSnake("a__b") == "aB")
  }

  @Test
  func convertFromSnakeCaseDecodesOpenMeteoShapedJSON() throws {
    struct Current: Decodable, Equatable {
      let temperature2M: Double
      let windSpeed10M: Double
      let isDay: Double
    }
    struct Daily: Decodable, Equatable {
      let temperature2MMax: [Double]
      let uvIndexMax: [Double]
    }
    struct Forecast: Decodable, Equatable {
      let current: Current
      let daily: Daily
    }
    let text = #"{"current":{"temperature_2m":1,"wind_speed_10m":89,"is_day":1},"daily":{"temperature_2m_max":[12.5,3],"uv_index_max":[2]}}"#
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let forecast = try decoder.decode(Forecast.self, from: Data(text.utf8))
    #expect(forecast.current == Current(temperature2M: 1, windSpeed10M: 89, isDay: 1))
    #expect(forecast.daily == Daily(temperature2MMax: [12.5, 3], uvIndexMax: [2]))
  }

  @Test
  func decodingErrorsAreFoundationsDecodingErrors() {
    struct Needs: Decodable { var count: Int }
    #expect {
      _ = try JSONDecoder().decode(Needs.self, from: Data("{}".utf8))
    } throws: { error in
      guard case DecodingError.keyNotFound(let key, _) = error else { return false }
      return key.stringValue == "count"
    }
    #expect {
      _ = try JSONDecoder().decode(Needs.self, from: Data(#"{"count":"3"}"#.utf8))
    } throws: { error in
      if case DecodingError.typeMismatch = error { return true }
      return false
    }
    #expect {
      _ = try JSONDecoder().decode(Needs.self, from: Data(#"{"count":null}"#.utf8))
    } throws: { error in
      if case DecodingError.valueNotFound = error { return true }
      return false
    }
    #expect(throws: EncodingError.self) { _ = try JSONEncoder().encode([Double.nan]) }
  }

  @Test
  func valueTypesArchiveAsFoundationAndCoreGraphicsDo() throws {
    #expect(try json(CGRect(x: 1, y: 2, width: 3, height: 4)) == "[[1,2],[3,4]]")
    #expect(try json(CGAffineTransform(translationX: 5, y: 6)) == "[1,0,0,1,5,6]")
    #expect(try json(Locale(identifier: "pt_BR")) == #"{"identifier":"pt_BR"}"#)
    #expect(try json(TimeZone(secondsFromGMT: -10_800)!) == #"{"identifier":"GMT-0300"}"#)
    #expect(try json(DateComponents(year: 2024, month: 2)) == #"{"month":2,"year":2024}"#)
    #expect(try json(UTType.json) == #""public.json""#)
    let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    #expect(try json(uuid) == #""E621E1F8-C36C-495A-93FC-0C247A3E6E5F""#)
    #expect(try JSONDecoder().decode(UUID.self, from: Data(#""E621E1F8-C36C-495A-93FC-0C247A3E6E5F""#.utf8)) == uuid)
  }

  @Test
  func urlStructureAndFileURLsMatchFoundation() {
    #expect(URL(string: "http://[invalid") == nil)
    #expect(URL(string: "http://host:port") == nil)
    #expect(URL(string: "https://[::1]:8080/a") != nil)
    #expect(URL(string: "relative/path?q=1") != nil)
    #expect(URL(fileURLWithPath: "/tmp/a b").absoluteString == "file:///tmp/a%20b")
    #expect(URL(fileURLWithPath: "/tmp/a b").path == "/tmp/a b")
    #expect(URL(fileURLWithPath: "/tmp").absoluteString == "file:///tmp/", "a directory of the file system ends in /")
  }
  @Test
  func integralNumbersWithAFractionOrExponentDecodeExactly() throws {
    // Past 2^53 a Double would round these; Foundation keeps every digit.
    #expect(try JSONDecoder().decode(Int64.self, from: Data("9007199254740993.0".utf8)) == 9_007_199_254_740_993)
    #expect(try JSONDecoder().decode(UInt64.self, from: Data("9007199254740993e0".utf8)) == 9_007_199_254_740_993)
    #expect(try JSONDecoder().decode(Int.self, from: Data("-12.50e1".utf8)) == -125)
    #expect(try JSONDecoder().decode(Int.self, from: Data("5E3".utf8)) == 5_000)
    #expect(try JSONDecoder().decode(Int.self, from: Data("1200e-2".utf8)) == 12)
    #expect(try JSONDecoder().decode(Int.self, from: Data("0.0".utf8)) == 0)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Int.self, from: Data("1.5".utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Int8.self, from: Data("1.28e2".utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(UInt.self, from: Data("-1.0".utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Int64.self, from: Data("1e100000".utf8)) }
  }

  @Test
  func numbersBeyondTheFloatingPointRangeAreRejected() throws {
    // Foundation rejects them under the default `.throw` strategy; only the string strategy yields infinities.
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Double.self, from: Data("1e400".utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Float.self, from: Data("3.5e38".utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Double.self, from: Data("-1e400".utf8)) }
    #expect(try JSONDecoder().decode(Float.self, from: Data("3.4e38".utf8)) == 3.4e38)
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    #expect(try decoder.decode(Double.self, from: Data(#""inf""#.utf8)) == .infinity)
  }

  @Test
  func keyStrategiesLeaveDictionaryKeysAlone() throws {
    // Foundation converts the coding keys of a model, never the keys of a `[String: V]`, which are data.
    struct Model: Codable, Equatable { var userName: String; var scores: [String: Int] }
    let model = Model(userName: "ana", scores: ["userID": 1, "user_id": 2])
    let text = try json(model) { $0.keyEncodingStrategy = .convertToSnakeCase }
    #expect(text == #"{"scores":{"userID":1,"user_id":2},"user_name":"ana"}"#)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    #expect(try decoder.decode(Model.self, from: Data(text.utf8)) == model)
    #expect(try decoder.decode([String: Int].self, from: Data(#"{"user_id":1,"userId":2}"#.utf8)) == ["user_id": 1, "userId": 2])
    #expect(try json(["someKey": 1]) { $0.keyEncodingStrategy = .convertToSnakeCase } == #"{"someKey":1}"#)
    // The values of a dictionary are still models, so their own keys are converted.
    let nested = try decoder.decode([String: Model].self, from: Data(#"{"a_b":{"user_name":"x","scores":{}}}"#.utf8))
    #expect(nested == ["a_b": Model(userName: "x", scores: [:])])
  }

  @Test
  func deeplyNestedInputIsRejectedInsteadOfOverflowingTheStack() throws {
    // Foundation stops at 512 levels. 12,000 nested arrays are about 24 KB and used to crash the recursive parser.
    let deep = Data(String(repeating: "[", count: 12_000).utf8) + Data(String(repeating: "]", count: 12_000).utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode([String].self, from: deep) }
    let deepObjects = Data(String(repeating: #"{"a":"#, count: 12_000).utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode([String: String].self, from: deepObjects) }
  }

  @Test
  func nestingAtTheLimitStillParses() throws {
    let limit = Data(String(repeating: "[", count: 512).utf8) + Data(String(repeating: "]", count: 512).utf8)
    _ = try JSONDecoder().decode(JSONNestingProbe.self, from: limit)
    let over = Data(String(repeating: "[", count: 513).utf8) + Data(String(repeating: "]", count: 513).utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(JSONNestingProbe.self, from: over) }
  }

  @Test
  func malformedUTF8InAStringIsRejectedNotRepaired() throws {
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(String.self, from: Data([0x22, 0xff, 0x22])) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode([String: Int].self, from: Data([0x7b, 0x22, 0xc3, 0x22, 0x3a, 0x31, 0x7d])) }
    #expect(try JSONDecoder().decode(String.self, from: Data("\"é😀\"".utf8)) == "é😀")
  }

}
