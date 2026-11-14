@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public enum PreviewLayout: Sendable {
  case device
  case sizeThatFits
  case fixed(width: Double, height: Double)
}

public struct PreviewDevice: ExpressibleByStringLiteral, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
}

extension View {
  public nonisolated func previewDisplayName(_ name: String?) -> Self { self }

  public nonisolated func previewLayout(_ layout: PreviewLayout) -> Self { self }

  public nonisolated func previewDevice(_ device: PreviewDevice?) -> Self { self }
}

extension Angle {
  public static prefix func - (value: Angle) -> Angle { Angle(radians: -value.radians) }
}

private enum DisplayScaleEnvironmentKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
  /// Device pixels per point. The browser lays out in CSS pixels, so views see 1 unless a host overrides it.
  public var displayScale: CGFloat {
    get { self[DisplayScaleEnvironmentKey.self] }
    set { self[DisplayScaleEnvironmentKey.self] = newValue }
  }
}

extension Image {
  public init(_ cgImage: CGImage, scale: CGFloat, label: Text) {
    self.init("")
    snapshot = cgImage.content
  }

  public init(decorative cgImage: CGImage, scale: CGFloat) {
    self.init("")
    snapshot = cgImage.content
  }
}

/// The system colors an iOS app passes to `Color(uiColor:)`. SwiftUI vends that initializer on iOS, so an application
/// does not import UIKit to use it; here the colors resolve to the same light and dark values as CSS `light-dark()`.
public struct UIColor: Hashable, Sendable {
  package let css: String

  package init(css: String) { self.css = css }
  private init(light: String, dark: String) { css = "light-dark(\(light), \(dark))" }

  public static let systemBackground = UIColor(light: "#FFFFFF", dark: "#000000")
  public static let secondarySystemBackground = UIColor(light: "#F2F2F7", dark: "#1C1C1E")
  public static let tertiarySystemBackground = UIColor(light: "#FFFFFF", dark: "#2C2C2E")
  public static let systemGroupedBackground = UIColor(light: "#F2F2F7", dark: "#000000")
  public static let secondarySystemGroupedBackground = UIColor(light: "#FFFFFF", dark: "#1C1C1E")
  public static let systemGray5 = UIColor(light: "#E5E5EA", dark: "#2C2C2E")
  public static let systemGray6 = UIColor(light: "#F2F2F7", dark: "#1C1C1E")
  public static let lightGray = UIColor(light: "#AAAAAA", dark: "#AAAAAA")
  public static let systemFill = UIColor(light: "rgb(120 120 128 / 0.20)", dark: "rgb(120 120 128 / 0.36)")
  public static let secondarySystemFill = UIColor(light: "rgb(120 120 128 / 0.16)", dark: "rgb(120 120 128 / 0.32)")
  public static let tertiarySystemFill = UIColor(light: "rgb(118 118 128 / 0.12)", dark: "rgb(118 118 128 / 0.24)")
  public static let quaternarySystemFill = UIColor(light: "rgb(116 116 128 / 0.08)", dark: "rgb(118 118 128 / 0.18)")
}

public extension Color {
  init(uiColor: UIColor) { self.init(css: uiColor.css) }
}

/// The system colors a macOS app passes to `Color(nsColor:)` (SwiftUI vends that initializer on macOS).
public struct NSColor: Hashable, Sendable {
  let css: String

  private init(light: String, dark: String) { css = "light-dark(\(light), \(dark))" }

  public static let windowBackgroundColor = NSColor(light: "#ECECEC", dark: "#323232")
  public static let controlBackgroundColor = NSColor(light: "#FFFFFF", dark: "#1E1E1E")
  public static let textBackgroundColor = NSColor(light: "#FFFFFF", dark: "#1E1E1E")
  public static let underPageBackgroundColor = NSColor(light: "#E5E5E5", dark: "#282828")
  public static let labelColor = NSColor(light: "rgb(0 0 0 / 0.85)", dark: "rgb(255 255 255 / 0.85)")
  public static let secondaryLabelColor = NSColor(light: "rgb(0 0 0 / 0.5)", dark: "rgb(255 255 255 / 0.55)")
  public static let tertiaryLabelColor = NSColor(light: "rgb(0 0 0 / 0.26)", dark: "rgb(255 255 255 / 0.25)")
  public static let quaternaryLabelColor = NSColor(light: "rgb(0 0 0 / 0.1)", dark: "rgb(255 255 255 / 0.1)")
  public static let separatorColor = NSColor(light: "rgb(0 0 0 / 0.1)", dark: "rgb(255 255 255 / 0.1)")
  public static let gridColor = NSColor(light: "#E6E6E6", dark: "#3B3B3B")
  public static let controlAccentColor = NSColor(light: "#007AFF", dark: "#0A84FF")
  public static let lightGray = NSColor(light: "#AAAAAA", dark: "#AAAAAA")
  public static let gray = NSColor(light: "#808080", dark: "#808080")
  public static let darkGray = NSColor(light: "#555555", dark: "#555555")
  public static let white = NSColor(light: "#FFFFFF", dark: "#FFFFFF")
  public static let black = NSColor(light: "#000000", dark: "#000000")
  public static let clear = NSColor(light: "transparent", dark: "transparent")
}

public extension Color {
  nonisolated init(nsColor: NSColor) { self.init(css: nsColor.css) }
}
