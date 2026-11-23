@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// Everyday SwiftUI text, symbol and interaction modifiers that map directly
/// onto browser primitives. Modifiers without a browser effect keep the
/// SwiftUI spelling and record semantic metadata (documented per modifier).
public extension Text {
  /// Where `lineLimit` truncation places the ellipsis.
  enum TruncationMode: Hashable, Sendable { case head, tail, middle 
    /// The CSS spelling of each case; SwiftUI does not expose a raw value.
    var rawValue: String {
      switch self {
      case .head: "head"
      case .tail: "tail"
      case .middle: "middle"
      }
    }
  }
}

public extension Image {
  /// Relative symbol size used by `imageScale(_:)`.
  enum Scale: Hashable, Sendable { case small, medium, large 
    /// The CSS spelling of each case; SwiftUI does not expose a raw value.
    var rawValue: String {
      switch self {
      case .small: "small"
      case .medium: "medium"
      case .large: "large"
      }
    }
  }
}

/// SF Symbol rendering modes. Browser symbols are single-color vector glyphs,
/// so every mode renders monochrome in the foreground style.
public struct SymbolRenderingMode: Hashable, Sendable {
  let rawValue: String
  public static let monochrome = SymbolRenderingMode(rawValue: "monochrome")
  public static let hierarchical = SymbolRenderingMode(rawValue: "hierarchical")
  public static let multicolor = SymbolRenderingMode(rawValue: "multicolor")
  public static let palette = SymbolRenderingMode(rawValue: "palette")
}

/// SF Symbol variants (`.fill`, `.circle`, ...), recorded as metadata.
public struct SymbolVariants: Hashable, Sendable {
  let rawValue: String
  public static let none = SymbolVariants(rawValue: "none")
  public static let fill = SymbolVariants(rawValue: "fill")
  public static let circle = SymbolVariants(rawValue: "circle")
  public static let square = SymbolVariants(rawValue: "square")
  public static let rectangle = SymbolVariants(rawValue: "rectangle")
  public static let slash = SymbolVariants(rawValue: "slash")
  public var fill: SymbolVariants { SymbolVariants(rawValue: rawValue + ".fill") }
}

/// Haptic feedback kinds for `sensoryFeedback(_:trigger:)`.
public struct SensoryFeedback: Hashable, Sendable {
  let rawValue: String
  public static let success = SensoryFeedback(rawValue: "success")
  public static let warning = SensoryFeedback(rawValue: "warning")
  public static let error = SensoryFeedback(rawValue: "error")
  public static let selection = SensoryFeedback(rawValue: "selection")
  public static let increase = SensoryFeedback(rawValue: "increase")
  public static let decrease = SensoryFeedback(rawValue: "decrease")
  public static let start = SensoryFeedback(rawValue: "start")
  public static let stop = SensoryFeedback(rawValue: "stop")
  public static let alignment = SensoryFeedback(rawValue: "alignment")
  public static let levelChange = SensoryFeedback(rawValue: "levelChange")
  public static let impact = SensoryFeedback(rawValue: "impact")
  public static func impact(weight: SensoryFeedback.Weight = .medium, intensity: Double = 1.0) -> SensoryFeedback { SensoryFeedback(rawValue: "impact") }
  public static func impact(flexibility: SensoryFeedback.Flexibility, intensity: Double = 1.0) -> SensoryFeedback { SensoryFeedback(rawValue: "impact") }
  public struct Weight: Hashable, Sendable {
    let rawValue: String
    public static let light = Weight(rawValue: "light")
    public static let medium = Weight(rawValue: "medium")
    public static let heavy = Weight(rawValue: "heavy")
  }
  public struct Flexibility: Hashable, Sendable {
    let rawValue: String
    public static let rigid = Flexibility(rawValue: "rigid")
    public static let solid = Flexibility(rawValue: "solid")
    public static let soft = Flexibility(rawValue: "soft")
  }
}

public extension View {
  /// Ellipsis placement for truncated text. `.tail` and `.head` are exact
  /// for single-line text (`.head` uses a right-to-left text-overflow box);
  /// `.middle` has no CSS primitive and truncates at the tail.
  nonisolated func truncationMode(_ mode: Text.TruncationMode) -> some View {
    _modified(_truncationModeModifier(mode))
  }

  /// Primary and secondary hierarchical styles. The primary style is the
  /// foreground; the secondary is exposed to content as `--secondary-style`.
  nonisolated func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
    let secondaryPaint = secondary._swiftUIWebCSSValue
    // The CSS variables let rendered secondary levels read the style; the environment lets a Canvas below read it too.
    return foregroundStyle(primary)._modified(_SemanticCompatibilityModifier(
      styles: ["--secondary-style": secondaryPaint],
      environment: { $0._foregroundSecondaryPaint = secondaryPaint }
    ))
  }

  nonisolated func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>(_ primary: S1, _ secondary: S2, _ tertiary: S3) -> some View {
    let secondaryPaint = secondary._swiftUIWebCSSValue, tertiaryPaint = tertiary._swiftUIWebCSSValue
    return foregroundStyle(primary)._modified(_SemanticCompatibilityModifier(
      styles: [
        "--secondary-style": secondaryPaint,
        "--tertiary-style": tertiaryPaint
      ],
      environment: {
        $0._foregroundSecondaryPaint = secondaryPaint
        $0._foregroundTertiaryPaint = tertiaryPaint
      }
    ))
  }

  /// Enables or disables user text selection in the subtree.
  nonisolated func textSelection<S: TextSelectability>(_ selectability: S) -> some View {
    _modified(_textSelectionModifier(allowsSelection: S.allowsSelection))
  }

  /// Sets the font width (condensed/expanded) of text in the subtree.
  nonisolated func fontWidth(_ width: Font.Width?) -> some View {
    _modified(_fontWidthModifier(width))
  }

  /// Lets text tighten inter-character spacing before truncating; the
  /// browser has no equivalent, so this is metadata only.
  nonisolated func allowsTightening(_ flag: Bool) -> some View {
    _modified(_allowsTighteningModifier(flag))
  }

  /// Scales symbol images relative to the surrounding font, like SF Symbols
  /// (`.small` ≈ 0.78em, `.medium` = 1em, `.large` ≈ 1.29em).
  nonisolated func imageScale(_ scale: Image.Scale) -> some View {
    _modified(_imageScaleModifier(scale))
  }

  /// Symbol rendering mode; browser symbols render monochrome.
  nonisolated func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View {
    _modified(_symbolRenderingModeModifier(mode))
  }

  /// Symbol variant preference, recorded for hosts that map symbol names.
  nonisolated func symbolVariant(_ variant: SymbolVariants) -> some View {
    _modified(_symbolVariantModifier(variant))
  }

  /// Pointer help text (iPadOS/macOS tooltip) as the browser tooltip.
  nonisolated func help(_ textKey: LocalizedStringKey) -> some View {
    _modified(_helpModifier(textKey.resolved))
  }

  @_disfavoredOverload nonisolated func help<S: StringProtocol>(_ text: S) -> some View {
    _modified(_helpModifier(String(text)))
  }

  nonisolated func help(_ text: Text) -> some View { help(text.value) }

  /// Marks privacy-sensitive content: its text is replaced by placeholders, and never written to the page, when the
  /// environment's `redactionReasons` holds `.privacy` (`.redacted(reason: .privacy)` above it), as on Apple platforms.
  nonisolated func privacySensitive(_ sensitive: Bool = true) -> some View {
    _modified(_PrivacySensitiveModifier(sensitive: sensitive))
  }

  /// Haptic feedback when `trigger` changes. Browsers expose no general
  /// haptics, so the trigger is observed and the feedback is recorded as
  /// metadata (`data-sensory-feedback`) without a side effect.
  nonisolated func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
    _modified(_SemanticCompatibilityModifier(attributes: ["data-sensory-feedback": feedback.rawValue]))
  }

  /// Sets the shape `ContainerRelativeShape` takes in the views below: its corner radius, which the page inherits
  /// (`--container-shape-radius`). Food Truck's cards clip to it and are rounded by the Grid's 12-point rectangle.
  nonisolated func containerShape<T: InsettableShape>(_ shape: T) -> some View {
    let radius = _containerShapeRadius(shape)
    return _modified(_SemanticCompatibilityModifier(
      attributes: ["data-container-shape": "true"], styles: ["--container-shape-radius": radius],
      environment: { $0._containerShapeRadius = radius }
    ))
  }
}
