
/// Whether text can be selected (`.textSelection(.enabled)`), as in SwiftUI.
public protocol TextSelectability {
  static var allowsSelection: Bool { get }
}

public struct EnabledTextSelectability: TextSelectability, Hashable, Sendable {
  public static var allowsSelection: Bool { true }
}

public struct DisabledTextSelectability: TextSelectability, Hashable, Sendable {
  public static var allowsSelection: Bool { false }
}

public extension TextSelectability where Self == EnabledTextSelectability {
  static var enabled: EnabledTextSelectability { EnabledTextSelectability() }
}

public extension TextSelectability where Self == DisabledTextSelectability {
  static var disabled: DisabledTextSelectability { DisabledTextSelectability() }
}

private enum ForegroundSecondaryPaintKey: EnvironmentKey { static let defaultValue: String? = nil }
private enum ForegroundTertiaryPaintKey: EnvironmentKey { static let defaultValue: String? = nil }

/// The secondary and tertiary foreground styles that `foregroundStyle(_:_:)` and `foregroundStyle(_:_:_:)` set for their
/// subtree (CSS paints). Nil when no such style is set, so levels 1 and 2 use their color mixes.
package extension EnvironmentValues {
  var _foregroundSecondaryPaint: String? {
    get { self[ForegroundSecondaryPaintKey.self] }
    set { self[ForegroundSecondaryPaintKey.self] = newValue }
  }
  var _foregroundTertiaryPaint: String? {
    get { self[ForegroundTertiaryPaintKey.self] }
    set { self[ForegroundTertiaryPaintKey.self] = newValue }
  }
}

