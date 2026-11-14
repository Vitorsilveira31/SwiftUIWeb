@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable

public enum ContentMode: Hashable, Sendable { case fit, fill 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .fit: "fit"
    case .fill: "fill"
    }
  }
}

public struct SafeAreaRegions: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let container = SafeAreaRegions(rawValue: 1 << 0)
  public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)
  public static let all: SafeAreaRegions = [.container, .keyboard]
}

public enum ScrollIndicatorVisibility: Hashable, Sendable { case automatic, visible, hidden, never 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .visible: "visible"
    case .hidden: "hidden"
    case .never: "never"
    }
  }
}

public enum ScrollDismissesKeyboardMode: Hashable, Sendable { case automatic, immediately, interactively, never 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .immediately: "immediately"
    case .interactively: "interactively"
    case .never: "never"
    }
  }
}

/// UIKit's `UITextContentType`, the value `textContentType(_:)` takes. UIKit is
/// not one of the frameworks the parity tool compares, so the stand-in keeps
/// UIKit's name and static members; the raw value is the browser `autocomplete`
/// token source.
public struct UITextContentType: Hashable, Sendable {
  package let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let name = UITextContentType(rawValue: "name")
  public static let namePrefix = UITextContentType(rawValue: "namePrefix")
  public static let nameSuffix = UITextContentType(rawValue: "nameSuffix")
  public static let givenName = UITextContentType(rawValue: "givenName")
  public static let familyName = UITextContentType(rawValue: "familyName")
  public static let nickname = UITextContentType(rawValue: "nickname")
  public static let username = UITextContentType(rawValue: "username")
  public static let password = UITextContentType(rawValue: "password")
  public static let newPassword = UITextContentType(rawValue: "newPassword")
  public static let oneTimeCode = UITextContentType(rawValue: "oneTimeCode")
  public static let emailAddress = UITextContentType(rawValue: "emailAddress")
  public static let telephoneNumber = UITextContentType(rawValue: "telephoneNumber")
  public static let URL = UITextContentType(rawValue: "URL")
  public static let addressCity = UITextContentType(rawValue: "addressCity")
  public static let addressState = UITextContentType(rawValue: "addressState")
  public static let countryName = UITextContentType(rawValue: "countryName")
}

public enum SubmitLabel: Hashable, Sendable { case done, go, join, next, `return`, route, search, send 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .done: "done"
    case .go: "go"
    case .join: "join"
    case .next: "next"
    case .`return`: "return"
    case .route: "route"
    case .search: "search"
    case .send: "send"
    }
  }
}

/// UIKit's `UIKeyboardType`, the value `keyboardType(_:)` takes (see `UITextContentType`).
/// UIKit declares it as an `NS_ENUM`, so it is an `Int`-backed enum like Apple's.
public enum UIKeyboardType: Int, Hashable, Sendable {
  case `default` = 0
  case asciiCapable = 1
  case numbersAndPunctuation = 2
  case URL = 3
  case numberPad = 4
  case phonePad = 5
  case namePhonePad = 6
  case emailAddress = 7
  case decimalPad = 8
  case twitter = 9
  case webSearch = 10
  case asciiCapableNumberPad = 11

  public static var alphabet: UIKeyboardType { .asciiCapable }

  /// The browser's `data-keyboard-type` spelling of each case. Underscored: not SwiftUI API.
  var _webName: String {
    switch self {
    case .default: "default"
    case .asciiCapable: "asciiCapable"
    case .numbersAndPunctuation: "numbersAndPunctuation"
    case .URL: "URL"
    case .numberPad: "numberPad"
    case .phonePad: "phonePad"
    case .namePhonePad: "namePhonePad"
    case .emailAddress: "emailAddress"
    case .decimalPad: "decimalPad"
    case .twitter: "twitter"
    case .webSearch: "webSearch"
    case .asciiCapableNumberPad: "asciiCapableNumberPad"
    }
  }
}

public enum TextInputAutocapitalization: Hashable, Sendable { case sentences, words, characters, never 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .sentences: "sentences"
    case .words: "words"
    case .characters: "characters"
    case .never: "never"
    }
  }
}

extension Text {
  /// SwiftUI's `Text.Case`, the value `textCase(_:)` takes.
  public enum Case: Hashable, Sendable { case uppercase, lowercase }
}

extension ShapeStyle where Self == Material {
  public static var ultraThinMaterial: Material { .ultraThin }

  public static var thinMaterial: Material { .thin }

  public static var regularMaterial: Material { .regular }

  public static var thickMaterial: Material { .thick }

  public static var ultraThickMaterial: Material { .ultraThick }

  /// SwiftUI's `ShapeStyle.bar`, the material of toolbars: `.background(.bar)`. The browser paints it exactly as
  /// `.regular`, so it is that case and adds no public name to `Material`.
  public static var bar: Material { .regular }
}

public struct BorderedListStyle: ListStyle {
  public init() {}
  /// See `InsetListStyle.init(alternatesRowBackgrounds:)`.
  public init(alternatesRowBackgrounds: Bool) {}
  public var _swiftUIWebListStyle: String { "bordered" }
}

public extension ListStyle where Self == BorderedListStyle {
  static var bordered: BorderedListStyle { BorderedListStyle() }

  static func bordered(alternatesRowBackgrounds: Bool) -> BorderedListStyle { BorderedListStyle(alternatesRowBackgrounds: alternatesRowBackgrounds) }
}

public nonisolated struct GraphicalDatePickerStyle: DatePickerStyle {
  public nonisolated init() {}
  public var _swiftUIWebDatePickerStyle: String { "graphical" }
}

@MainActor @preconcurrency public struct WheelDatePickerStyle: DatePickerStyle {
  @MainActor @preconcurrency public init() {}
  public var _swiftUIWebDatePickerStyle: String { "wheel" }
}

public nonisolated struct StepperFieldDatePickerStyle: DatePickerStyle {
  public nonisolated init() {}
  public var _swiftUIWebDatePickerStyle: String { "stepperField" }
}

public extension DatePickerStyle where Self == GraphicalDatePickerStyle {
  @MainActor @preconcurrency static var graphical: GraphicalDatePickerStyle { GraphicalDatePickerStyle() }
}

public extension DatePickerStyle where Self == WheelDatePickerStyle {
  @MainActor @preconcurrency static var wheel: WheelDatePickerStyle { WheelDatePickerStyle() }
}

public extension DatePickerStyle where Self == StepperFieldDatePickerStyle {
  @MainActor @preconcurrency static var stepperField: StepperFieldDatePickerStyle { StepperFieldDatePickerStyle() }
}

public nonisolated struct _DatePickerStyleModifier<Style: DatePickerStyle>: ViewModifier {
  public let style: Style
  public init(style: Style) { self.style = style }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    context.environment.datePickerStyle = style._swiftUIWebDatePickerStyle
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-date-picker-style"] = style._swiftUIWebDatePickerStyle
  }
}

/// SwiftUI's content transition: how a view's content (a text's characters) changes in an animated commit. The browser
/// host (Tools/transition-host.js) plays it; `token` names the kind, `direction` and `value` steer `numericText`.
/// Two numeric-text transitions are equal whatever their direction, as the kind is what a view's identity depends on.
public struct ContentTransition: Equatable, Sendable {
  let token: String
  /// `up`, `down`, or `value` (the direction follows `value` from one commit to the next).
  let direction: String?
  let value: Double?
  /// The options of a symbol effect: its speed and repeats, which the host plays a replace with.
  let options: SymbolEffectOptions?
  init(token: String, direction: String? = nil, value: Double? = nil, options: SymbolEffectOptions? = nil) { self.token = token; self.direction = direction; self.value = value; self.options = options }
  public static func == (lhs: ContentTransition, rhs: ContentTransition) -> Bool { lhs.token == rhs.token }
  public static let identity = ContentTransition(token: "identity")
  public static let opacity = ContentTransition(token: "opacity")
  public static let interpolate = ContentTransition(token: "interpolate")
  /// The changed digits roll in from below (or from above when `countsDown`), blurring as they pass.
  public static func numericText(countsDown: Bool = false) -> ContentTransition { ContentTransition(token: "numeric-text", direction: countsDown ? "down" : "up") }
  /// The changed digits roll up when `value` grows and down when it shrinks.
  public static func numericText(value: Double) -> ContentTransition { ContentTransition(token: "numeric-text", direction: "value", value: value) }
}

public enum ScrollBounceBehavior: Hashable, Sendable { case automatic, always, basedOnSize 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .always: "always"
    case .basedOnSize: "basedOnSize"
    }
  }
}

public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
  public init() {}
  public var _swiftUIWebScrollTargetBehavior: String { "paging" }
}

public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
  public init() {}
  public var _swiftUIWebScrollTargetBehavior: String { "view-aligned" }
}

public extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
  static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

public extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
  static var viewAligned: ViewAlignedScrollTargetBehavior { ViewAlignedScrollTargetBehavior() }
}

private func _scrollRect(x: Double, y: Double, width: Double, height: Double) -> CGRect {
  return CGRect(x: x, y: y, width: width, height: height)
}

/// The value reported by SwiftUI's scroll geometry callbacks.  It is a
/// backend-neutral snapshot; browser hosts fill it from native scroll
/// metrics while non-browser renderers can provide their own measurements.
public struct ScrollGeometry: Equatable, Sendable {
  public var contentOffset: CGPoint
  public var contentSize: CGSize
  public var containerSize: CGSize
  public var visibleRect: CGRect
  public var contentInsets: EdgeInsets

  package init(
    contentOffset: CGPoint = _SwiftUIWebGeometryDefaults.zeroPoint,
    contentSize: CGSize = _SwiftUIWebGeometryDefaults.zeroSize,
    containerSize: CGSize = _SwiftUIWebGeometryDefaults.zeroSize,
    visibleRect: CGRect = _SwiftUIWebGeometryDefaults.zeroRect,
    contentInsets: EdgeInsets = EdgeInsets()
  ) {
    self.contentOffset = contentOffset
    self.contentSize = contentSize
    self.containerSize = containerSize
    self.visibleRect = visibleRect
    self.contentInsets = contentInsets
  }

  @_spi(Renderer) public static func _decode(_ raw: String) -> ScrollGeometry? {
    let values = raw.split(separator: ",").compactMap { Double($0) }
    guard values.count >= 10 else { return nil }
    return ScrollGeometry(
      contentOffset: CGPoint(x: values[0], y: values[1]),
      contentSize: CGSize(width: values[2], height: values[3]),
      containerSize: CGSize(width: values[4], height: values[5]),
      visibleRect: _scrollRect(x: values[6], y: values[7], width: values[8], height: values[9]),
      contentInsets: values.count >= 14 ? EdgeInsets(top: values[10], leading: values[11], bottom: values[12], trailing: values[13]) : EdgeInsets()
    )
  }
}

extension ScrollGeometry {
  public static func == (lhs: ScrollGeometry, rhs: ScrollGeometry) -> Bool {
    lhs.contentOffset.x == rhs.contentOffset.x && lhs.contentOffset.y == rhs.contentOffset.y &&
      lhs.contentSize.width == rhs.contentSize.width && lhs.contentSize.height == rhs.contentSize.height &&
      lhs.containerSize.width == rhs.containerSize.width && lhs.containerSize.height == rhs.containerSize.height &&
      lhs.visibleRect.origin.x == rhs.visibleRect.origin.x && lhs.visibleRect.origin.y == rhs.visibleRect.origin.y &&
      lhs.visibleRect.size.width == rhs.visibleRect.size.width && lhs.visibleRect.size.height == rhs.visibleRect.size.height &&
      lhs.contentInsets == rhs.contentInsets
  }
}

public enum ScrollPhase: Hashable, Sendable {
  case idle, tracking, interacting, decelerating, animating

  /// Decodes the browser's event spelling; the inverse of `rawValue`.
  static func _decoded(_ raw: String) -> ScrollPhase? {
    [ScrollPhase.idle, .tracking, .interacting, .decelerating, .animating].first { $0.rawValue == raw }
  }

  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .idle: "idle"
    case .tracking: "tracking"
    case .interacting: "interacting"
    case .decelerating: "decelerating"
    case .animating: "animating"
    }
  }
}

public struct ScrollPhaseChangeContext: Sendable {
  public let geometry: ScrollGeometry
  package init(geometry: ScrollGeometry = ScrollGeometry()) { self.geometry = geometry }
}

/// The phase passed to a scroll transition closure.  `value` follows
/// SwiftUI's convention: -1 for leading, 0 for identity and 1 for trailing.
public enum ScrollTransitionPhase: Hashable, Sendable {
  case identity, topLeading, bottomTrailing
  public var isIdentity: Bool { self == .identity }
  public var value: Double {
    switch self { case .identity: return 0; case .topLeading: return -1; case .bottomTrailing: return 1 }
  }
}

public extension VisualEffect {
  func scaleEffect(_ value: Double) -> Self { scaleEffect(x: value, y: value) }

  func rotationEffect(_ angle: Angle) -> Self { _swiftUIWebAppendingTransform("rotate(\(angle.radians)rad)") }
}

/// SwiftUI's empty visual effect: the value a scroll-transition closure starts from. Its
/// effect methods return the same type, so `phase.isIdentity ? content : content.opacity(0.5)`
/// keeps compiling.
public struct EmptyVisualEffect: VisualEffect, Hashable, Sendable {
  public var _swiftUIWebProperties: [String: String]
  public init() { _swiftUIWebProperties = [:] }
  public init(_swiftUIWebProperties: [String: String]) { self._swiftUIWebProperties = _swiftUIWebProperties }
  public var _swiftUIWebEncoded: String { _encoded }
  @_spi(Renderer) public var _encoded: String {
    _swiftUIWebProperties.keys.sorted().map { "\($0)=\(_swiftUIWebProperties[$0] ?? "")" }.joined(separator: ";")
  }
}

public struct PresentationDetent: Hashable, Sendable {
  package enum Kind: Hashable, Sendable { case medium, large, fraction(Double), height(Double) }
  package let kind: Kind
  init(_ kind: Kind) { self.kind = kind }
  public static let medium = PresentationDetent(.medium)
  public static let large = PresentationDetent(.large)
  public static func fraction(_ value: Double) -> PresentationDetent { PresentationDetent(.fraction(value)) }
  public static func height(_ value: Double) -> PresentationDetent { PresentationDetent(.height(value)) }

  /// A compact, deterministic representation used by browser hosts and
  /// value events.  It deliberately mirrors SwiftUI's detent cases rather
  /// than exposing any DOM/CSS concepts through the public API.
  @_spi(Browser) public var _swiftUIWebIdentifier: String {
    // Explicit spelling: Embedded Swift cannot describe enum payloads.
    switch kind {
    case .medium: return "medium"
    case .large: return "large"
    case .fraction(let value): return "fraction(" + String(value) + ")"
    case .height(let value): return "height(" + String(value) + ")"
    }
  }

  @_spi(Browser) public init?(_swiftUIWebIdentifier identifier: String) {
    let value = identifier
    switch value {
    case "medium": self = .medium
    case "large": self = .large
    default:
      if value.hasPrefix("fraction("), value.hasSuffix(")") {
        let raw = value.dropFirst("fraction(".count).dropLast()
        guard let number = Double(raw) else { return nil }
        self = .fraction(number)
      } else if value.hasPrefix("height("), value.hasSuffix(")") {
        let raw = value.dropFirst("height(".count).dropLast()
        guard let number = Double(raw) else { return nil }
        self = .height(number)
      } else {
        return nil
      }
    }
  }
}

public enum PresentationBackgroundInteraction: Hashable, Sendable { case automatic, enabled, disabled 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .enabled: "enabled"
    case .disabled: "disabled"
    }
  }
}

public enum ToolbarRole: Hashable, Sendable { case automatic, editor, browser 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .editor: "editor"
    case .browser: "browser"
    }
  }
}

package nonisolated struct OpenURLModifier: ViewModifier {
  private let action: @MainActor (URL) -> Void
  public init(action: @escaping @MainActor (URL) -> Void) {
    self.action = action
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-open-url-handler"] = "true"
    // Hosts that receive an external URL can dispatch this value event to the
    // same Fiber node.  No browser/JavaScript type crosses the Core boundary.
    node.events["openURL"] = _EventHandler(name: "openURL", action: { raw in
      action(URL(raw))
    })
  }
}

public extension Image {
  /// The browser always antialiases.
  func antialiased(_ isAntialiased: Bool) -> Image { self }
}

public extension View {
  /// Receives URLs delivered by a host (for example a browser deep link).
  /// The callback is stored as backend-neutral event metadata; browser hosts
  /// may invoke it when the document is opened or history changes.
  nonisolated func onOpenURL(perform action: @escaping (URL) -> ()) -> some View {
    modifier(OpenURLModifier(action: _mainActor(action)))
  }

  // SwiftUI's `View` spellings of the content-mode modifiers, for any view
  // (an `Image` uses its own overloads above).
  nonisolated func scaledToFit() -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scaledToFit2Modifier())
  }

  nonisolated func scaledToFill() -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scaledToFill2Modifier())
  }

  nonisolated func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_aspectRatioModifier(aspectRatio, contentMode: contentMode))
  }

  nonisolated func fontWeight(_ weight: Font.Weight?) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_fontWeightModifier(weight))
  }

  /// Paint order among siblings. CSS `z-index` accepts integers only, so
  /// whole values map exactly and fractional values round away from zero
  /// (keeping them above/below a `0` sibling). The browser layout
  /// positions stack children absolutely, so the value orders siblings.
  nonisolated func zIndex(_ value: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_zIndexModifier(value))
  }

  @_disfavoredOverload nonisolated func zIndex(_ value: Float) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    zIndex(Double(value))
  }

  nonisolated func fontDesign(_ design: Font.Design?) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_fontDesignModifier(design))
  }

  nonisolated func italic(_ active: Bool = true) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_italicModifier(active))
  }

  nonisolated func strikethrough(_ active: Bool = true, color: Color? = nil) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    var styles: _NodeValues = ["text-decoration-line": active ? "line-through" : "none"]
    if let color { styles["text-decoration-color"] = color.cssValue }
    return modifier(_SemanticCompatibilityModifier(styles: styles))
  }

  @_disfavoredOverload nonisolated func kerning(_ value: Float) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { kerning(Double(value)) }

  nonisolated func kerning(_ value: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_kerningModifier(value)) }

  @_disfavoredOverload nonisolated func baselineOffset(_ value: Float) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { baselineOffset(Double(value)) }

  nonisolated func baselineOffset(_ value: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_baselineOffsetModifier(value)) }

  @_disfavoredOverload nonisolated func lineSpacing(_ value: Float) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { lineSpacing(Double(value)) }

  /// SwiftUI adds the spacing to the font's natural line height (about 1.2em for
  /// the studio's fonts), which CSS cannot express with `normal`, so the browser
  /// uses 1.2em as the base.
  nonisolated func lineSpacing(_ value: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_lineSpacingModifier(value)) }

  nonisolated func monospacedDigit() -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_monospacedDigitModifier()) }

  nonisolated func textCase(_ textCase: Text.Case?) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_textCaseModifier(textCase)) }

  nonisolated func textInputAutocapitalization(_ behavior: TextInputAutocapitalization?) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_textInputAutocapitalizationModifier(behavior))
  }

  nonisolated func contentTransition(_ transition: ContentTransition) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_contentTransitionModifier(transition))
  }

  nonisolated func listStyle<S: ListStyle>(_ style: S) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_listStyleModifier(style._swiftUIWebListStyle)) }

  nonisolated func formStyle<S: FormStyle>(_ style: S) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_formStyleModifier(style._swiftUIWebFormStyle)) }

  nonisolated func datePickerStyle<S: DatePickerStyle>(_ style: S) -> ModifiedContent<Self, _DatePickerStyleModifier<S>> { modifier(_DatePickerStyleModifier(style: style)) }

  nonisolated func buttonBorderShape(_ shape: ButtonBorderShape) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_buttonBorderShapeModifier(shape))
  }

  nonisolated func swipeActions<Actions: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: @escaping () -> Actions) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    let edgeName = edge == .leading ? "leading" : "trailing"
    return modifier(_swipeActionsModifier(edge: edgeName, allowsFullSwipe: allowsFullSwipe, content: { AnyView(content()) }))
  }

  nonisolated func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = .vertical) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_scrollBounceBehaviorModifier(behavior, axes: axes)) }

  nonisolated func presentationDragIndicator(_ visibility: Visibility) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_presentationDragIndicatorModifier(visibility)) }

  /// iOS 18's spelling of `toolbar(_:for:)`, which Apple deprecates; it records the same per-placement visibility.
  nonisolated func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarModifier(visibility, for: bars)) }

  nonisolated func toolbarBackground(_ visibility: Visibility, for bars: ToolbarPlacement...) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarBackgroundModifier(visibility, for: bars)) }

  nonisolated func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacement...) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarBackgroundStyleModifier(style._swiftUIWebCSSValue, for: bars)) }

  nonisolated func toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarBackgroundModifier(visibility, for: bars)) }

  /// Reports a value derived from the nearest scroll container's geometry.
  /// The transform runs only after the browser's native metrics change and
  /// the action is coalesced by the normal Fiber refresh scheduler.
  nonisolated func onScrollGeometryChange<Value: Equatable>(for type: Value.Type, of transform: @escaping (ScrollGeometry) -> Value, action: @escaping (Value, Value) -> Void) -> some View {
    modifier(ScrollGeometryChangeModifier(transform: transform, action: _mainActor(action)))
  }

  nonisolated func onScrollPhaseChange(_ action: @escaping (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void) -> some View {
    modifier(ScrollPhaseChangeModifier(action: _mainActor(action)))
  }

  nonisolated func onScrollPhaseChange(_ action: @escaping (ScrollPhase, ScrollPhase) -> Void) -> some View {
    modifier(ScrollPhaseChangeModifier(action: _mainActor({ old, new, _ in action(old, new) })))
  }

  /// Receives the IDs of currently visible scroll targets.  This is backed by
  /// one IntersectionObserver per scroll surface and is therefore suitable
  /// for virtualized lists as well as ordinary ScrollViews.  `threshold` is
  /// accepted for SwiftUI source compatibility; the browser observer reports
  /// visibility with its own rule rather than the fraction given here.
  nonisolated func onScrollTargetVisibilityChange<ID: Hashable>(idType: ID.Type, threshold: Double = 0.5, _ action: @escaping ([ID]) -> Void) -> some View {
    modifier(ScrollTargetVisibilityModifier(action: _mainActor(action)))
  }

  nonisolated func highPriorityGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View { modifier(GestureCompatibilityModifier(gesture: gesture, mask: mask, priority: "high")) }
}

package nonisolated struct ScrollGeometryChangeModifier<Value: Equatable>: ViewModifier {
  private let transform: (ScrollGeometry) -> Value
  private let pairAction: (@MainActor (Value, Value) -> Void)?
  private let singleAction: (@MainActor (Value) -> Void)?

  fileprivate init(transform: @escaping (ScrollGeometry) -> Value, action: @escaping @MainActor (Value, Value) -> Void) {
    self.transform = transform; pairAction = action; singleAction = nil
  }
  fileprivate init(transform: @escaping (ScrollGeometry) -> Value, singleAction: @escaping @MainActor (Value) -> Void) {
    self.transform = transform; pairAction = nil; self.singleAction = singleAction
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-scroll-geometry-change"] = "true"
    let key = context._fiberPath.description + "#scroll-geometry"
    let stateStore = context.stateStore
    let transform = self.transform
    let pairAction = self.pairAction
    let singleAction = self.singleAction
    node.events["scrollGeometry"] = _EventHandler(name: "scrollGeometry", action: { raw in
      guard let geometry = ScrollGeometry._decode(raw) else { return }
      let value = transform(geometry)
      let result = stateStore.rememberChange(key, value: value)
      guard result.initial || result.changed else { return }
      if let pairAction { pairAction(result.previous ?? value, value) }
      else { singleAction?(value) }
    })
  }
}

package nonisolated struct ScrollPhaseChangeModifier: ViewModifier {
  fileprivate let action: @MainActor (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void
  fileprivate init(action: @escaping @MainActor (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void) {
    self.action = action
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-scroll-phase-change"] = "true"
    let key = context._fiberPath.description + "#scroll-phase"
    let stateStore = context.stateStore
    let action = self.action
    node.events["scrollPhase"] = _EventHandler(name: "scrollPhase", action: { raw in
      let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
      guard let new = parts.first.flatMap(ScrollPhase._decoded) else { return }
      let geometry = parts.count > 1 ? (ScrollGeometry._decode(parts[1]) ?? ScrollGeometry()) : ScrollGeometry()
      let result = stateStore.rememberChange(key, value: new)
      guard result.initial || result.changed else { return }
      action(result.previous ?? .idle, new, ScrollPhaseChangeContext(geometry: geometry))
    })
  }
}

/// SwiftUI's scroll-transition configuration: `interactive` follows the scroll position continuously, `animated` switches
/// phase with an animation when the view crosses the threshold, `identity` never transitions. The browser host
/// (Tools/transition-host.js, ScrollTransitionHost) reads what `attributes` publishes.
public struct ScrollTransitionConfiguration: Sendable {
  let mode: String
  let curve: String
  let timing: String?
  let threshold: Threshold

  init(mode: String, curve: String = "ease-in-out", timing: String? = nil, threshold: Threshold = .visible) {
    self.mode = mode; self.curve = curve; self.timing = timing; self.threshold = threshold
  }

  public static func animated(_ animation: Animation = .default) -> ScrollTransitionConfiguration {
    ScrollTransitionConfiguration(mode: "animated", timing: animation._transitionTiming)
  }
  public static let animated = ScrollTransitionConfiguration.animated()
  public static func interactive(timingCurve: UnitCurve = .easeInOut) -> ScrollTransitionConfiguration {
    ScrollTransitionConfiguration(mode: "interactive", curve: timingCurve.cssEasing)
  }
  public static let interactive = ScrollTransitionConfiguration.interactive()
  public static let identity = ScrollTransitionConfiguration(mode: "identity")
  public func animation(_ animation: Animation) -> ScrollTransitionConfiguration {
    ScrollTransitionConfiguration(mode: mode, curve: curve, timing: animation._transitionTiming, threshold: threshold)
  }
  public func threshold(_ threshold: ScrollTransitionConfiguration.Threshold) -> ScrollTransitionConfiguration {
    ScrollTransitionConfiguration(mode: mode, curve: curve, timing: timing, threshold: threshold)
  }

  /// How much of the view must be visible for it to be at identity.
  public struct Threshold: Sendable {
    /// The visible fraction (0...1), or the distance from the center for `centered`.
    let amount: Double
    let inset: Double
    let centered: Bool
    init(amount: Double, inset: Double = 0, centered: Bool = false) { self.amount = amount; self.inset = inset; self.centered = centered }
    /// At identity only while entirely visible.
    public static let visible = Threshold(amount: 1)
    /// At identity while any of it is visible.
    public static let hidden = Threshold(amount: 0)
    /// At identity only when centered in the scroll view.
    public static var centered: ScrollTransitionConfiguration.Threshold { Threshold(amount: 1, centered: true) }
    /// At identity while at least `amount` of it is visible.
    public static func visible(_ amount: Double) -> ScrollTransitionConfiguration.Threshold { Threshold(amount: min(max(amount, 0), 1)) }
    public func interpolated(towards other: ScrollTransitionConfiguration.Threshold, amount: Double) -> ScrollTransitionConfiguration.Threshold {
      let t = min(max(amount, 0), 1)
      return Threshold(amount: self.amount + (other.amount - self.amount) * t, inset: inset + (other.inset - inset) * t, centered: t < 0.5 ? centered : other.centered)
    }
    /// The scroll view's edges, for this threshold, moved inwards by `distance`.
    public func inset(by distance: Double) -> ScrollTransitionConfiguration.Threshold { Threshold(amount: amount, inset: inset + distance, centered: centered) }
  }

  var attributes: _NodeValues {
    var values: _NodeValues = ["data-scroll-transition-mode": mode, "data-scroll-transition-curve": curve]
    values["data-scroll-transition-threshold"] = threshold.centered ? "centered" : String(threshold.amount)
    if threshold.inset != 0 { values["data-scroll-transition-inset"] = String(threshold.inset) }
    if let timing { values["data-scroll-transition-timing"] = timing }
    return values
  }
}

nonisolated struct _ScrollTransitionModifier<Effect: VisualEffect>: ViewModifier {
  let configuration: ScrollTransitionConfiguration
  let axis: Axis?
  let transition: (EmptyVisualEffect, ScrollTransitionPhase) -> Effect

  @MainActor func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-scroll-transition"] = "true"
    for (key, value) in configuration.attributes { node.attributes[key] = value }
    if let axis {
      node.attributes["data-scroll-transition-axis"] = axis == .horizontal ? "horizontal" : "vertical"
    }
    let empty = EmptyVisualEffect()
    node.attributes["data-scroll-transition-identity"] = transition(empty, .identity)._swiftUIWebEncoded
    node.attributes["data-scroll-transition-leading"] = transition(empty, .topLeading)._swiftUIWebEncoded
    node.attributes["data-scroll-transition-trailing"] = transition(empty, .bottomTrailing)._swiftUIWebEncoded
  }
}

/// One id of a `scrollTargetVisibility` event: `%XX` escapes decoded, nil when an escape or the bytes are not valid.
func _scrollPercentDecoded(_ text: String) -> String? {
  let bytes = Array(text.utf8)
  var output: [UInt8] = []
  output.reserveCapacity(bytes.count)
  var index = 0
  func hex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: return byte - 0x30
    case 0x41...0x46: return byte - 0x37
    case 0x61...0x66: return byte - 0x57
    default: return nil
    }
  }
  while index < bytes.count {
    if bytes[index] == 0x25 {
      guard index + 2 < bytes.count, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) else { return nil }
      output.append(high << 4 | low)
      index += 3
    } else {
      output.append(bytes[index])
      index += 1
    }
  }
  return String(validating: output, as: UTF8.self)
}

package nonisolated struct ScrollTargetVisibilityModifier<ID: Hashable>: ViewModifier {
  fileprivate let action: @MainActor ([ID]) -> Void
  fileprivate init(action: @escaping @MainActor ([ID]) -> Void) {
    self.action = action
  }
  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    node.attributes["data-scroll-target-visibility"] = "true"
    let action = self.action
    node.events["scrollTargetVisibility"] = _EventHandler(name: "scrollTargetVisibility", action: { raw in
      // The host writes each id percent-encoded and joins them with ",", so an id that holds a "," or a "%" reads back whole.
      let values = raw.split(separator: ",").compactMap { _scrollPercentDecoded(String($0)) }
      let ids = values.compactMap { _scrollDecodeID($0, as: ID.self) }
      action(ids)
    })
  }
}

public extension Gesture {
  var _swiftUIWebGestureName: String {
    _swiftUIWebTypeName(Self.self)
  }
}

public extension AnyGesture {
  @MainActor var _swiftUIWebGestureName: String {
    _makeRendererGesture().name
  }
}

public extension View {
  @_disfavoredOverload nonisolated func cornerRadius(_ radius: Float) -> some View { cornerRadius(Double(radius)) }

  nonisolated func scaleEffect(_ scale: Double, anchor: UnitPoint = .center) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scaleEffectModifier(scale, anchor: anchor))
  }

  nonisolated func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scaleEffectModifier(x: x, y: y, anchor: anchor))
  }

  nonisolated func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_rotationEffectModifier(angle, anchor: anchor))
  }

  nonisolated func transformEffect(_ transform: CGAffineTransform) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_transformEffectModifier(transform))
  }

  nonisolated func rotation3DEffect(_ angle: Angle, axis: (x: Double, y: Double, z: Double), anchor: UnitPoint = .center, anchorZ: Double = 0) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_rotation3DEffectModifier(angle, axis: axis, anchor: anchor, anchorZ: anchorZ))
  }

  nonisolated func rotation3DEffect(_ angle: Angle, axis: (x: Double, y: Double, z: Double), anchor: UnitPoint = .center, anchorZ: Double = 0, perspective: Double = 1) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_rotation3DEffectModifier(angle, axis: axis, anchor: anchor, anchorZ: anchorZ, perspective: perspective))
  }

  nonisolated func minimumScaleFactor(_ factor: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_minimumScaleFactorModifier(factor)) }

  nonisolated func shadow(color: Color = Color("rgba(0,0,0,0.15)"), radius: Double, x: Double = 0, y: Double = 0) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_shadowModifier(color: color, radius: radius, x: x, y: y))
  }

  nonisolated func allowsHitTesting(_ enabled: Bool) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_allowsHitTestingModifier(enabled)) }

  nonisolated func labelsHidden() -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_labelsHiddenModifier())
  }

  nonisolated func safeAreaPadding(_ edges: Edge.Set = .all, _ length: Double? = nil) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { contentMargins(edges, length) }

  nonisolated func safeAreaPadding(_ insets: EdgeInsets) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    _safeAreaPadding(.all, insets)
  }

  nonisolated func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_ignoresSafeAreaModifier())
  }

  nonisolated func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_scrollIndicatorsModifier(visibility)) }

  nonisolated func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_scrollDismissesKeyboardModifier(mode)) }

  nonisolated func scrollContentBackground(_ visibility: Visibility) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scrollContentBackgroundModifier(visibility))
  }

  /// Controls whether the host applies a native edge fade/effect.  Browsers
  /// do not expose SwiftUI's material edge effect directly, so the semantic
  /// marker lets the design-system stylesheet choose the closest CSS affordance.
  nonisolated func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scrollEdgeEffectHiddenModifier(hidden, for: edges))
  }

  nonisolated func defaultScrollAnchor(_ anchor: UnitPoint) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_defaultScrollAnchorModifier(anchor))
  }

  nonisolated func scrollDisabled(_ disabled: Bool) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scrollDisabledModifier(disabled))
  }

  nonisolated func scrollClipDisabled(_ disabled: Bool = true) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scrollClipDisabledModifier(disabled))
  }

  nonisolated func interactiveDismissDisabled(_ disabled: Bool = true) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_interactiveDismissDisabledModifier(disabled)) }

  nonisolated func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_presentationBackgroundInteractionModifier(interaction)) }

  nonisolated func blendMode(_ mode: BlendMode) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_blendModeModifier(mode))
  }

  nonisolated func compositingGroup() -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_compositingGroupModifier())
  }

  nonisolated func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_drawingGroupModifier(opaque: opaque, colorMode: colorMode))
  }

  nonisolated func brightness(_ amount: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_brightnessModifier(amount))
  }

  nonisolated func contrast(_ amount: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_contrastModifier(amount))
  }

  nonisolated func saturation(_ amount: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_saturationModifier(amount))
  }

  nonisolated func grayscale(_ amount: Double) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_grayscaleModifier(amount))
  }

  nonisolated func colorInvert() -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_colorInvertModifier())
  }

  nonisolated func hueRotation(_ angle: Angle) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_hueRotationModifier(angle))
  }

  nonisolated func toolbarColorScheme(_ colorScheme: ColorScheme?, for bars: ToolbarPlacement...) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarColorSchemeModifier(colorScheme, for: bars)) }

  nonisolated func toolbarRole(_ role: ToolbarRole) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_toolbarRoleModifier(role)) }

  nonisolated func textContentType(_ type: UITextContentType?) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_textContentTypeModifier(type)) }

  nonisolated func submitLabel(_ label: SubmitLabel) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_submitLabelModifier(label)) }

  nonisolated func keyboardType(_ type: UIKeyboardType) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_keyboardTypeModifier(type)) }

  nonisolated func autocorrectionDisabled(_ disabled: Bool = true) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_autocorrectionDisabledModifier(disabled)) }

  nonisolated func dynamicTypeSize(_ size: DynamicTypeSize) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_dynamicTypeSizeModifier(size)) }

  nonisolated func pickerStyle<S: PickerStyle>(_ style: S) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    let value = style._swiftUIWebPickerStyle
    return modifier(_SemanticCompatibilityModifier(attributes: ["data-picker-style": value], environment: { $0._pickerStyle = value }))
  }

  nonisolated func textFieldStyle<S: TextFieldStyle>(_ style: S) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    let value = style._swiftUIWebTextFieldStyle
    return modifier(_SemanticCompatibilityModifier(attributes: ["data-text-field-style": value], environment: { $0._textFieldStyle = value }))
  }

  /// Reports whether a view intersects its nearest scroll viewport. The
  /// browser adapter can realize this metadata with IntersectionObserver;
  /// static/WASI hosts retain the API and leave the callback untouched.
  nonisolated func onScrollVisibilityChange(threshold: Double = 0, _ action: @escaping (Bool) -> Void) -> some View {
    modifier(ScrollVisibilityModifier(threshold: threshold, action: action))
  }

  nonisolated func simultaneousGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View { modifier(GestureCompatibilityModifier(gesture: gesture, mask: mask, priority: "simultaneous")) }

  nonisolated func scrollTargetLayout(isEnabled: Bool = true) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_scrollTargetLayoutModifier(isEnabled: isEnabled)) }

  /// Scroll snapping. The attribute value is the host stylesheet token
  /// (`paging`, `view-aligned`, `continuous`) mapped to CSS scroll-snap.
  nonisolated func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_scrollTargetBehaviorModifier(behavior._swiftUIWebScrollTargetBehavior))
  }

  nonisolated func scrollPosition(id: Binding<(some Hashable)?>, anchor: UnitPoint? = nil) -> some View { _scrollPositionByID(id, anchor: anchor) }

  fileprivate nonisolated func _scrollPositionByID<ID: Hashable>(_ id: Binding<ID?>, anchor: UnitPoint?) -> some View {
    modifier(ScrollPositionModifier(binding: id, anchor: anchor))
  }

  nonisolated func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
    modifier(ScrollPositionValueModifier(binding: position, anchor: anchor))
  }

  /// SwiftUI's scroll transition. The closure receives the empty effect and the phase; the browser
  /// host evaluates the three phases and applies the encoded effects while scrolling.
  nonisolated func scrollTransition(
    _ configuration: ScrollTransitionConfiguration = .interactive,
    axis: Axis? = nil,
    transition: @escaping @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect
  ) -> some View {
    _scrollTransition(configuration, axis: axis, transition: transition)
  }

  fileprivate nonisolated func _scrollTransition<Effect: VisualEffect>(
    _ configuration: ScrollTransitionConfiguration,
    axis: Axis?,
    transition: @escaping @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> Effect
  ) -> some View {
    modifier(_ScrollTransitionModifier(configuration: configuration, axis: axis, transition: transition))
  }

  nonisolated func navigationBarBackButtonHidden(_ hidden: Bool = true) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_navigationBarBackButtonHiddenModifier(hidden)) }

  nonisolated func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    var sides: Edge.Set = []
    if edges.contains(.top) { sides.insert(.top) }
    if edges.contains(.bottom) { sides.insert(.bottom) }
    return modifier(_listRowSeparatorModifier(visibility, edges: sides))
  }

  nonisolated func listRowBackground<Background: View>(_ background: Background) -> some View { modifier(BackgroundModifier(content: { background }, alignment: .center, isListRowBackground: true)) }

  nonisolated func listRowInsets(_ insets: EdgeInsets?) -> ModifiedContent<Self, _SemanticCompatibilityModifier> { modifier(_listRowInsetsModifier(insets)) }

  nonisolated func contentMargins(_ edges: Edge.Set = .all, _ length: Double?, for placement: ContentMarginPlacement = .automatic) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_contentMarginsModifier(edges, length, for: placement))
  }

  /// SwiftUI also accepts per-edge insets for scroll content. Preserve the
  /// shape instead of forcing applications to split this into four modifiers;
  /// the renderer emits only the selected edges and keeps the placement token
  /// available to browser hosts.
  nonisolated func contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets, for placement: ContentMarginPlacement = .automatic) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    modifier(_contentMarginsModifier(edges, insets, for: placement))
  }

  nonisolated func contentMargins(_ length: Double, for placement: ContentMarginPlacement = .automatic) -> ModifiedContent<Self, _SemanticCompatibilityModifier> {
    contentMargins(.all, length, for: placement)
  }

  nonisolated func onLongPressGesture(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10, perform action: @escaping () -> Void, onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
    modifier(LongPressCompatibilityModifier(minimumDuration: minimumDuration, maximumDistance: Double(maximumDistance), action: _mainActor(action), onPressingChanged: _mainActor(onPressingChanged)))
  }
}

func _cssBlendMode(_ mode: BlendMode) -> String {
  switch mode {
  case .normal: return "normal"
  case .colorDodge: return "color-dodge"
  case .colorBurn: return "color-burn"
  case .softLight: return "soft-light"
  case .hardLight: return "hard-light"
  // CSS has no operator for these: an element cannot composite against what is painted under it.
  case .sourceAtop, .destinationOver, .destinationOut: return "normal"
  case .plusDarker: return "plus-darker"
  case .plusLighter: return "plus-lighter"
  default: return mode.rawValue
  }
}

public extension VStack {
  @_disfavoredOverload nonisolated init(alignment: HorizontalAlignment = .center, spacing: Float?, @ViewBuilder content: () -> Content) { self.init(alignment: alignment, spacing: spacing.map(Double.init), content: content) }
}

public extension HStack {
  @_disfavoredOverload nonisolated init(alignment: VerticalAlignment = .center, spacing: Float?, @ViewBuilder content: () -> Content) { self.init(alignment: alignment, spacing: spacing.map(Double.init), content: content) }
}

public extension LazyVStack {
  @_disfavoredOverload nonisolated init(alignment: HorizontalAlignment = .center, spacing: Float?, @ViewBuilder content: () -> Content) { self.init(alignment: alignment, spacing: spacing.map(Double.init), content: content) }
}

public extension LazyHStack {
  @_disfavoredOverload nonisolated init(alignment: VerticalAlignment = .center, spacing: Float?, @ViewBuilder content: () -> Content) { self.init(alignment: alignment, spacing: spacing.map(Double.init), content: content) }
}
