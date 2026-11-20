// Stand-in for Apple's OS so the unmodified Food Truck sources import it in the browser build.
@_exported import SwiftUIWeb

/// How a logged value is shown in a unified-logging message (`privacy: .public`).
public struct OSLogPrivacy: Sendable {
  public static let auto = OSLogPrivacy()
  public static let `public` = OSLogPrivacy()
  public static let `private` = OSLogPrivacy()
}

/// A unified-logging message, written as a string with interpolations. A browser has no unified log, so the message is
/// kept as text (`Logger` writes nothing).
public struct OSLogMessage: ExpressibleByStringInterpolation, Sendable {
  public struct StringInterpolation: StringInterpolationProtocol, Sendable {
    public init(literalCapacity: Int, interpolationCount: Int) {}
    public mutating func appendLiteral(_ literal: String) {}
    public mutating func appendInterpolation<T>(_ value: T, privacy: OSLogPrivacy = .auto) {}
  }
  public init(stringLiteral value: String) {}
  public init(stringInterpolation: StringInterpolation) {}
}

/// Apple's unified logging. The iPad version of Food Truck logs the URLs it opens; a browser build has no system log to
/// write to.
public struct Logger: Sendable {
  public init() {}
  public init(subsystem: String, category: String) {}
  public func log(_ message: OSLogMessage) {}
  public func debug(_ message: OSLogMessage) {}
  public func info(_ message: OSLogMessage) {}
  public func notice(_ message: OSLogMessage) {}
  public func error(_ message: OSLogMessage) {}
  public func fault(_ message: OSLogMessage) {}
}
