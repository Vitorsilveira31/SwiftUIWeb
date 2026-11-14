/// A log message: a string literal with interpolated values, each with its privacy (`OSLogMessage`).
public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral, Sendable {
  public let interpolation: OSLogInterpolation

  public init(stringInterpolation: OSLogInterpolation) { interpolation = stringInterpolation }

  public init(stringLiteral value: String) {
    var interpolation = OSLogInterpolation(literalCapacity: value.utf8.count, interpolationCount: 0)
    interpolation.appendLiteral(value)
    self.interpolation = interpolation
  }
}

/// The parts of a log message. A value is kept with whether its privacy hides it: `.private` and `.sensitive` do,
/// `.public` does not, and `.auto` hides text and described values but not numbers or Booleans, as Apple's does.
public struct OSLogInterpolation: StringInterpolationProtocol, Sendable {
  struct Segment: Sendable {
    let text: String
    let isPrivate: Bool
  }

  var segments: [Segment] = []

  public init(literalCapacity: Int, interpolationCount: Int) {
    segments.reserveCapacity(interpolationCount * 2 + 1)
  }

  public mutating func appendLiteral(_ literal: String) {
    segments.append(Segment(text: literal, isPrivate: false))
  }

  public mutating func appendInterpolation(_ value: @autoclosure () -> String, privacy: OSLogPrivacy = .auto) {
    segments.append(Segment(text: value(), isPrivate: privacy.hides(scalar: false)))
  }

  public mutating func appendInterpolation<T: BinaryInteger>(_ value: @autoclosure () -> T, privacy: OSLogPrivacy = .auto) {
    segments.append(Segment(text: String(value()), isPrivate: privacy.hides(scalar: true)))
  }

  public mutating func appendInterpolation(_ value: @autoclosure () -> Double, privacy: OSLogPrivacy = .auto) {
    segments.append(Segment(text: String(value()), isPrivate: privacy.hides(scalar: true)))
  }

  public mutating func appendInterpolation(_ value: @autoclosure () -> Float, privacy: OSLogPrivacy = .auto) {
    segments.append(Segment(text: String(value()), isPrivate: privacy.hides(scalar: true)))
  }

  public mutating func appendInterpolation(_ value: @autoclosure () -> Bool, privacy: OSLogPrivacy = .auto) {
    segments.append(Segment(text: value() ? "true" : "false", isPrivate: privacy.hides(scalar: true)))
  }

  public mutating func appendInterpolation<T: CustomStringConvertible>(
    _ value: @autoclosure () -> T, privacy: OSLogPrivacy = .auto
  ) {
    segments.append(Segment(text: value().description, isPrivate: privacy.hides(scalar: false)))
  }

  /// The message, with each value its privacy hides written `<private>` when `redacting`.
  func rendered(redacting: Bool) -> String {
    var text = ""
    for segment in segments { text += redacting && segment.isPrivate ? "<private>" : segment.text }
    return text
  }
}

/// Whether a logged value may be shown (`OSLogPrivacy`).
public struct OSLogPrivacy: Equatable, Sendable {
  enum Kind: Equatable, Sendable { case auto, open, hidden }
  let kind: Kind

  /// Shown everywhere.
  public static let `public` = OSLogPrivacy(kind: .open)
  /// Hidden once no debugger is attached (in a release build).
  public static let `private` = OSLogPrivacy(kind: .hidden)
  /// Hidden once no debugger is attached (in a release build).
  public static let sensitive = OSLogPrivacy(kind: .hidden)
  /// Text and described values are private; numbers and Booleans are public.
  public static let auto = OSLogPrivacy(kind: .auto)

  /// How a hidden value is replaced. The browser writes `<private>` for each mask.
  public struct Mask: Equatable, Sendable {
    let rawValue: UInt8
    public static let hash = Mask(rawValue: 1)
    public static let none = Mask(rawValue: 0)
  }

  public static func `private`(mask _: Mask) -> OSLogPrivacy { .private }
  public static func sensitive(mask _: Mask) -> OSLogPrivacy { .sensitive }
  public static func auto(mask _: Mask) -> OSLogPrivacy { .auto }

  func hides(scalar: Bool) -> Bool {
    switch kind {
    case .open: false
    case .hidden: true
    case .auto: !scalar
    }
  }
}
