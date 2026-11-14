import SwiftUIWebBrowserIO

/// Apple's unified logging API (`import OSLog`) for the browser. An application aliases `OSLog` to this module
/// (`-module-alias OSLog=WebOSLog`), so the `Logger` it writes for iOS and Android logs to the browser's console:
/// `debug` and `trace` to `console.debug`, `info` to `console.info`, `log` and `notice` to `console.log`, `warning`
/// and `error` to `console.warn` and `console.error`, `critical` and `fault` to `console.error`. Each line starts with
/// the logger's subsystem and category. Off the browser (a native build, a test) the line is printed.
public struct Logger: Sendable {
  let subsystem: String
  let category: String

  /// A logger with no subsystem or category.
  public init() {
    subsystem = ""
    category = ""
  }

  public init(subsystem: String, category: String) {
    self.subsystem = subsystem
    self.category = category
  }

  public func log(_ message: OSLogMessage) { write(message, .default) }
  public func log(level: OSLogType, _ message: OSLogMessage) { write(message, level) }
  public func trace(_ message: OSLogMessage) { write(message, .debug) }
  public func debug(_ message: OSLogMessage) { write(message, .debug) }
  public func info(_ message: OSLogMessage) { write(message, .info) }
  public func notice(_ message: OSLogMessage) { write(message, .default) }
  public func warning(_ message: OSLogMessage) { write(message, .error, warning: true) }
  public func error(_ message: OSLogMessage) { write(message, .error) }
  public func critical(_ message: OSLogMessage) { write(message, .fault) }
  public func fault(_ message: OSLogMessage) { write(message, .fault) }

  /// The console line for `message`: `[subsystem:category]` (or the one that is set) before the text.
  func line(_ message: OSLogMessage, redacting: Bool) -> String {
    let text = message.interpolation.rendered(redacting: redacting)
    let tag = subsystem.isEmpty ? category : category.isEmpty ? subsystem : subsystem + ":" + category
    return tag.isEmpty ? text : "[" + tag + "] " + text
  }

  private func write(_ message: OSLogMessage, _ type: OSLogType, warning: Bool = false) {
    let level: BrowserConsole.Level
    switch type {
    case .debug: level = .debug
    case .info: level = .info
    case .error: level = warning ? .warning : .error
    case .fault: level = .error
    default: level = .log
    }
    let text = line(message, redacting: Logger.redactsPrivateValues)
    if !BrowserConsole.write(text, level: level) { print(text) }
  }

  /// A release build hides private values (`<private>`), as Apple's unified logging does once no debugger is
  /// attached; a debug build shows them, as Xcode's console does.
  #if SWIFTUIWEB_RELEASE
    static let redactsPrivateValues = true
  #else
    static let redactsPrivateValues = false
  #endif
}

/// The level of a log message (`OSLogType`).
public struct OSLogType: Equatable, Hashable, Sendable {
  public let rawValue: UInt8
  public init(_ rawValue: UInt8) { self.rawValue = rawValue }

  public static let `default` = OSLogType(0x00)
  public static let info = OSLogType(0x01)
  public static let debug = OSLogType(0x02)
  public static let error = OSLogType(0x10)
  public static let fault = OSLogType(0x11)
}
