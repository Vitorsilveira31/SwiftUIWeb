import SwiftUIWebLocking

/// Where `Date()` reads the current time. Native hosts start with the operating system's wall clock; the browser
/// installs its own at the runtime boundary. Without either (Embedded and WASI fixtures) the deterministic zero keeps
/// renderer-only output reproducible.
@_spi(Renderer) public enum SwiftUIWebDateRuntime {
  public typealias NowProvider = @Sendable () -> Double
  /// Non-generic holder: a closure kept in a generic `_Locked<NowProvider>` is
  /// re-abstracted on every access, and Embedded Swift chains those thunks
  /// until the WASM stack overflows (one extra pair per `Date()` created).
  private final class Storage: @unchecked Sendable {
    var provider: NowProvider = SwiftUIWebDateRuntime.hostClock
  }
  private static let storage = Storage()
  private static let hostClock: NowProvider = { _swiftUIWebHostWallClockSeconds() ?? 0 }

  /// Replaces the clock; `nil` restores the host's own.
  public static func install(now provider: NowProvider?) {
    storage.provider = provider ?? hostClock
  }

  static var nowInterval: Double { storage.provider() }
}

public struct Date: Hashable, Sendable, Comparable {
  public var timeIntervalSince1970: TimeInterval
  public init() { timeIntervalSince1970 = SwiftUIWebDateRuntime.nowInterval }
  public init(timeIntervalSince1970: TimeInterval) { self.timeIntervalSince1970 = timeIntervalSince1970 }
  public init(timeIntervalSinceReferenceDate interval: TimeInterval) {
    timeIntervalSince1970 = interval + 978_307_200
  }
  public static var now: Date { Date() }
  /// Apple's values: the first moment of year 1 and of year 4001 (UTC).
  public static let distantPast = Date(timeIntervalSinceReferenceDate: -63_114_076_800)
  public static let distantFuture = Date(timeIntervalSinceReferenceDate: 63_113_904_000)
  public var timeIntervalSinceReferenceDate: TimeInterval { timeIntervalSince1970 - 978_307_200 }
  public func timeIntervalSince(_ date: Date) -> TimeInterval { timeIntervalSince1970 - date.timeIntervalSince1970 }
  public func addingTimeInterval(_ timeInterval: TimeInterval) -> Date { Date(timeIntervalSince1970: timeIntervalSince1970 + timeInterval) }
  public mutating func addTimeInterval(_ timeInterval: TimeInterval) { timeIntervalSince1970 += timeInterval }
  public static func < (lhs: Date, rhs: Date) -> Bool {
    lhs.timeIntervalSince1970 < rhs.timeIntervalSince1970
  }
}
public typealias TimeInterval = Double

#if hasFeature(Embedded)
extension URL: EmbeddedCodable {
  public func _embeddedJSONValue() throws -> _EmbeddedJSONValue { .string(absoluteString) }
  public static func _embeddedDecodeJSONValue(_ value: _EmbeddedJSONValue) throws -> URL {
    guard case .string(let string) = value else { throw _EmbeddedCodableError.typeMismatch }
    guard let url = URL(string: string) else { throw _EmbeddedCodableError.typeMismatch }
    return url
  }
}

extension Date: EmbeddedCodable {
  public func _embeddedJSONValue() throws -> _EmbeddedJSONValue {
    switch EmbeddedCodableStrategies.date { case .deferredToDate: return .number(timeIntervalSinceReferenceDate); case .secondsSince1970: return .number(timeIntervalSince1970); case .millisecondsSince1970: return .number(timeIntervalSince1970 * 1000) }
  }
  public static func _embeddedDecodeJSONValue(_ value: _EmbeddedJSONValue) throws -> Date {
    guard case .number(let seconds) = value else { throw _EmbeddedCodableError.typeMismatch }
    switch EmbeddedCodableStrategies.date { case .deferredToDate: return Date(timeIntervalSinceReferenceDate: seconds); case .secondsSince1970: return Date(timeIntervalSince1970: seconds); case .millisecondsSince1970: return Date(timeIntervalSince1970: seconds / 1000) }
  }
}
#else
// Codable in Foundation's own formats, so an archive written on Apple decodes here and the reverse. JSONEncoder
// special-cases all three (date and data strategies, URL as its string); other coders see these forms.

extension Date: Codable {
  /// Foundation's form: the seconds since the reference date (2001-01-01 UTC) as one Double.
  public init(from decoder: any Decoder) throws {
    self.init(timeIntervalSinceReferenceDate: try decoder.singleValueContainer().decode(Double.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(timeIntervalSinceReferenceDate)
  }
}

extension Data: Codable {
  /// Foundation's form: the bytes as an unkeyed list of UInt8.
  public init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var bytes: [UInt8] = []
    if let count = container.count { bytes.reserveCapacity(count) }
    while !container.isAtEnd { bytes.append(try container.decode(UInt8.self)) }
    self.init(bytes)
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    for byte in self { try container.encode(byte) }
  }
}

extension URL: Codable {
  private enum CodingKeys: String, CodingKey { case base, relative }
  /// Foundation's form: a keyed `relative` string (and `base`, which this URL value never carries).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let relative = try container.decode(String.self, forKey: .relative)
    let base = try container.decodeIfPresent(URL.self, forKey: .base)
    let string = base.map { _resolve(relative, against: $0.absoluteString) } ?? relative
    guard let url = URL(string: string) else {
      throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid URL string."))
    }
    self = url
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(absoluteString, forKey: .relative)
  }
}

/// `relative` against `base` for the archived (base, relative) pair: absolute references stand alone, the rest
/// replace the base's last path segment.
private func _resolve(_ relative: String, against base: String) -> String {
  let separator = Array("://".utf8)
  if relative.utf8.firstRange(of: separator) != nil || base.isEmpty { return relative }
  let baseBytes = Array(base.utf8)
  if relative.hasPrefix("/") {
    guard let scheme = baseBytes.firstRange(of: separator) else { return relative }
    let authorityEnd = baseBytes[scheme.upperBound...].firstIndex(of: UInt8(ascii: "/")) ?? baseBytes.endIndex
    return String(decoding: baseBytes[..<authorityEnd], as: UTF8.self) + relative
  }
  guard let slash = baseBytes.lastIndex(of: UInt8(ascii: "/")) else { return relative }
  return String(decoding: baseBytes[...slash], as: UTF8.self) + relative
}
#endif
