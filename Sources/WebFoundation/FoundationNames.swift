// Foundation-named APIs for the Embedded/browser build, so application code written once against Foundation
// (`ProcessInfo`, `URLQueryItem`, `Locale.preferredLanguages`; `UserDefaults` is SwiftUIWebCore's) compiles unchanged for the browser, where
// an app aliases `Foundation` to this module (`-module-alias Foundation=WebFoundation`).
//
// Native builds keep the real Foundation: these declarations exist only where Foundation does not, with the same gate
// SwiftUIWebCore uses for `Locale`, `Date` and friends.
import SwiftUIWebCore
import SwiftUIWebFeatures

/// `ProcessInfo.processInfo.environment[key]`, backed by `WebEnvironment` (the host page's
/// `<meta name="runtime-environment">` entries in the browser).
public final class ProcessInfo: @unchecked Sendable {
  public static let processInfo = ProcessInfo()
  public let environment = ProcessEnvironment()
  private init() {}
}

/// The subscript-only view of the environment that `ProcessInfo.environment` returns.
public struct ProcessEnvironment: Sendable {
  public subscript(key: String) -> String? { WebEnvironment.value(forKey: key) }
}

/// One `name=value` pair of a query string.
public struct URLQueryItem: Sendable, Equatable {
  public var name: String
  public var value: String?

  public init(name: String, value: String?) {
    self.name = name
    self.value = value
  }
}

extension Locale {
  /// The language the host page asked for (navigator.language unless the application pinned one), most preferred first.
  public static var preferredLanguages: [String] {
    guard let language = WebEnvironment.value(forKey: "SWIFTUIWEB_LANGUAGE") else { return [] }
    return [language]
  }
}
