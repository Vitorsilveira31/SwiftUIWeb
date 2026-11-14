@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
// Codable in Foundation's and CoreGraphics' own archive forms, so a value archived on an Apple platform decodes here
// and the reverse. Embedded Swift has no Codable; its builds use EmbeddedCodable instead.
#if !hasFeature(Embedded)

// MARK: Geometry: unkeyed lists, as CoreGraphics archives them

extension CGPoint: Codable {
  public init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    self.init(x: try container.decode(Double.self), y: try container.decode(Double.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(x)
    try container.encode(y)
  }
}

extension CGSize: Codable {
  public init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    self.init(width: try container.decode(Double.self), height: try container.decode(Double.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(width)
    try container.encode(height)
  }
}

extension CGRect: Codable {
  public init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    self.init(origin: try container.decode(CGPoint.self), size: try container.decode(CGSize.self))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(origin)
    try container.encode(size)
  }
}

extension CGAffineTransform: Codable {
  public init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    self.init(
      a: try container.decode(Double.self), b: try container.decode(Double.self),
      c: try container.decode(Double.self), d: try container.decode(Double.self),
      tx: try container.decode(Double.self), ty: try container.decode(Double.self)
    )
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.unkeyedContainer()
    for value in [a, b, c, d, tx, ty] { try container.encode(value) }
  }
}

// MARK: Locale, time zone and calendar: keyed by identifier, as Foundation archives them

private enum _IdentifierCodingKeys: String, CodingKey { case identifier }

extension Locale: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: _IdentifierCodingKeys.self)
    self.init(identifier: try container.decode(String.self, forKey: .identifier))
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: _IdentifierCodingKeys.self)
    try container.encode(identifier, forKey: .identifier)
  }
}

extension TimeZone: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: _IdentifierCodingKeys.self)
    let identifier = try container.decode(String.self, forKey: .identifier)
    guard let zone = TimeZone(identifier: identifier) else {
      throw DecodingError.dataCorruptedError(forKey: .identifier, in: container, debugDescription: "Invalid TimeZone identifier.")
    }
    self = zone
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: _IdentifierCodingKeys.self)
    try container.encode(identifier, forKey: .identifier)
  }
}

// Foundation writes an identifier as its CLDR name.
extension Calendar.Identifier: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    switch try container.decode(String.self) {
    case "gregorian": self = .gregorian
    case "iso8601": self = .iso8601
    case let name: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown calendar identifier \(name)")
    }
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .gregorian: try container.encode("gregorian")
    case .iso8601: try container.encode("iso8601")
    }
  }
}

extension Calendar: Codable {
  private enum CodingKeys: String, CodingKey { case identifier, locale, timeZone, firstWeekday, minimumDaysInFirstWeek }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(identifier: try container.decode(Identifier.self, forKey: .identifier))
    locale = try container.decodeIfPresent(Locale.self, forKey: .locale)
    if let zone = try container.decodeIfPresent(TimeZone.self, forKey: .timeZone) { timeZone = zone }
    if let weekday = try container.decodeIfPresent(Int.self, forKey: .firstWeekday) { firstWeekday = weekday }
    if let days = try container.decodeIfPresent(Int.self, forKey: .minimumDaysInFirstWeek) { minimumDaysInFirstWeek = days }
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(identifier, forKey: .identifier)
    try container.encodeIfPresent(locale, forKey: .locale)
    try container.encode(timeZone, forKey: .timeZone)
    try container.encode(firstWeekday, forKey: .firstWeekday)
    try container.encode(minimumDaysInFirstWeek, forKey: .minimumDaysInFirstWeek)
  }
}

// MARK: Date components: one key per set component, as Foundation archives them

extension DateComponents: Codable {
  private enum CodingKeys: String, CodingKey {
    case calendar, timeZone, era, year, month, day, hour, minute, second, nanosecond
    case weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear, yearForWeekOfYear
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    calendar = try container.decodeIfPresent(Calendar.self, forKey: .calendar)
    timeZone = try container.decodeIfPresent(TimeZone.self, forKey: .timeZone)
    era = try container.decodeIfPresent(Int.self, forKey: .era)
    year = try container.decodeIfPresent(Int.self, forKey: .year)
    month = try container.decodeIfPresent(Int.self, forKey: .month)
    day = try container.decodeIfPresent(Int.self, forKey: .day)
    hour = try container.decodeIfPresent(Int.self, forKey: .hour)
    minute = try container.decodeIfPresent(Int.self, forKey: .minute)
    second = try container.decodeIfPresent(Int.self, forKey: .second)
    nanosecond = try container.decodeIfPresent(Int.self, forKey: .nanosecond)
    weekday = try container.decodeIfPresent(Int.self, forKey: .weekday)
    weekdayOrdinal = try container.decodeIfPresent(Int.self, forKey: .weekdayOrdinal)
    quarter = try container.decodeIfPresent(Int.self, forKey: .quarter)
    weekOfMonth = try container.decodeIfPresent(Int.self, forKey: .weekOfMonth)
    weekOfYear = try container.decodeIfPresent(Int.self, forKey: .weekOfYear)
    yearForWeekOfYear = try container.decodeIfPresent(Int.self, forKey: .yearForWeekOfYear)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(calendar, forKey: .calendar)
    try container.encodeIfPresent(timeZone, forKey: .timeZone)
    try container.encodeIfPresent(era, forKey: .era)
    try container.encodeIfPresent(year, forKey: .year)
    try container.encodeIfPresent(month, forKey: .month)
    try container.encodeIfPresent(day, forKey: .day)
    try container.encodeIfPresent(hour, forKey: .hour)
    try container.encodeIfPresent(minute, forKey: .minute)
    try container.encodeIfPresent(second, forKey: .second)
    try container.encodeIfPresent(nanosecond, forKey: .nanosecond)
    try container.encodeIfPresent(weekday, forKey: .weekday)
    try container.encodeIfPresent(weekdayOrdinal, forKey: .weekdayOrdinal)
    try container.encodeIfPresent(quarter, forKey: .quarter)
    try container.encodeIfPresent(weekOfMonth, forKey: .weekOfMonth)
    try container.encodeIfPresent(weekOfYear, forKey: .weekOfYear)
    try container.encodeIfPresent(yearForWeekOfYear, forKey: .yearForWeekOfYear)
  }
}
#endif
