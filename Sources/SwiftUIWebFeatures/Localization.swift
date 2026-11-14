@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

public extension String {
  /// The key `String(localized:)` takes; Foundation's own type natively.
  struct LocalizationValue: Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public typealias StringInterpolation = LocalizedStringKey.StringInterpolation
    var key: LocalizedStringKey
    public init(_ value: String) { key = LocalizedStringKey(value) }
    public init(stringLiteral value: String) { key = LocalizedStringKey(value) }
    public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
      key = LocalizedStringKey(stringInterpolation: stringInterpolation)
    }
  }

  /// Foundation's `String(localized:)` taking a resource, which carries its own locale.
  @_disfavoredOverload
  init(localized resource: LocalizedStringResource) {
    self = LocalizationTable.resolve(resource.key, language: resource.languageIdentifier)
  }

  /// Foundation's `String(localized:)`, answered from the registered tables.
  init(localized keyAndValue: String.LocalizationValue, table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
    self = keyAndValue.key.resolved
  }
}

/// Foundation's `LocalizedStringResource`: a localized string plus the locale
/// to resolve it in, so one call site can show a language other than the
/// process's. A function taking one is also what Xcode's string extraction
/// reads, which is why the studio's `tr(_:)` helper has this parameter type.
public struct LocalizedStringResource: Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public typealias StringInterpolation = LocalizedStringKey.StringInterpolation
  var key: LocalizedStringKey
  public var locale: Locale

  public init(_ value: String.LocalizationValue, table: String? = nil, locale: Locale = .current, comment: StaticString? = nil) {
    key = value.key
    self.locale = locale
  }
  public init(stringLiteral value: String) { key = LocalizedStringKey(value); locale = .current }
  public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
    key = LocalizedStringKey(stringInterpolation: stringInterpolation)
    locale = .current
  }

  /// `nil` selects the table's preferred language (the locale is the default one).
  var languageIdentifier: String? {
    let identifier = locale.identifier
    return identifier.isEmpty || identifier == "en_US_POSIX" ? nil : identifier
  }
}
