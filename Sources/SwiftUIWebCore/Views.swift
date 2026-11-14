@_spi(Renderer) import SwiftUIWebTransferable

/// Foundation's `Bundle`, as far as a web page has one: the application's resources are served next to the page, so a
/// bundle is only a name that `Image(_:bundle:)` and `String(localized:bundle:)` accept. SwiftPM generates
/// `Bundle.module` for a target with resources, as on Apple platforms.
public struct Bundle: Hashable, Sendable {
  public let bundleIdentifier: String?
  public init?(identifier: String) { bundleIdentifier = identifier }
  private init(main: Void) { bundleIdentifier = nil }
  public static let main = Bundle(main: ())
}

// `Date` and `TimeInterval` live in SwiftUIWebTransferable (Date.swift), next to `Data`
// and `URL`, so the JSON coders there can name them.
@_exported import struct SwiftUIWebTransferable.Date
@_exported import typealias SwiftUIWebTransferable.TimeInterval

/// A small Foundation-free locale value used by the SwiftUI-shaped
/// environment on WASI/Embedded toolchains.  Native builds use
/// `Foundation.Locale` through the `Locale` typealias below.
public struct Locale: Hashable, Sendable {
  public let identifier: String
  /// `Locale.current`: the visitor's locale, which the browser's formatters apply. Its `identifier` names en_US_POSIX,
  /// the fixed locale Swift code sees; a `Locale(identifier: "en_US_POSIX")` asked for by name keeps that locale.
  package let _isVisitorLocale: Bool
  public init(identifier: String) { self.identifier = identifier; _isVisitorLocale = false }
  private init(visitorLocaleNamed identifier: String) { self.identifier = identifier; _isVisitorLocale = true }
  /// The locale a browser formatter is given: empty (its own, the visitor's) for `Locale.current`.
  package var _formatterTag: String { _isVisitorLocale ? "" : identifier }
  public var languageCode: String? {
    identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init)
  }
  public var regionCode: String? {
    let pieces = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" })
    guard pieces.count > 1 else { return nil }
    return String(pieces[1])
  }
  public var timeZone: TimeZone { .current }
  public var calendar: Calendar { .current }
  public static let current = Locale(visitorLocaleNamed: "en_US_POSIX")
  public static let autoupdatingCurrent = Locale.current
}

public struct Text {
  public typealias Body = Never
  package var value: String
  /// The subset of SwiftUI's date styles that can be represented consistently
  /// by a host-neutral renderer.  Browser hosts may localize the resulting
  /// value; static/WASI hosts keep the deterministic textual fallback.
  public enum DateStyle: Hashable, Sendable {
    case date
    case time
    case relative
    case offset
    case timer
  }

  // Internal so the FoundationInternationalization-backed date initializer
  // can be emitted in its own source unit and discarded by the linker when
  // date formatting is not used. This does not change the public API.
  let dateStyle: DateStyle?
  /// Ordered CSS declarations recorded by the Text-returning modifiers
  /// (`bold()`, `font(_:)`, `foregroundColor(_:)`, ...). Later entries win.
  package var _textStyles: [_TextStyleDeclaration] = []
  /// Styled runs produced by `Text + Text`. Empty for an ordinary Text. A
  /// concatenation renders as one text leaf with inline child runs, so it
  /// wraps as a single paragraph and is measured as one intrinsic leaf.
  package var _textRuns: [Text] = []
  /// A run that is an image drawn in the text line (`Text(Image)`, and the custom emoji of rich text).
  var _inlineImage: _InlineImage?
  /// The values `customAttribute(_:)` put on the text, for a `TextRenderer`.
  var _customAttributes = _TextCustomAttributes()
  /// Whether a custom attribute is set on this text (`customAttribute(_:)`), for the modules above this one.
  package var _hasCustomAttributes: Bool { !_customAttributes.isEmpty }

  /// `Text("key")` looks the key up in the registered translations, like
  /// SwiftUI; a `String` variable (the generic overload) is shown as is.
  /// `tableName`, `bundle` and `comment` are accepted for SwiftUI source
  /// compatibility; translations come from the application's registered tables.
  public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
    self.value = key.resolved; dateStyle = nil; _expandInlineImages()
  }
  @_disfavoredOverload public init<S: StringProtocol>(_ value: S) { self.value = String(value); dateStyle = nil }
  public init(verbatim value: String) { self.value = value; dateStyle = nil }
  @_spi(Renderer) public init(_swiftUIWebValue value: String, dateStyle: DateStyle?) {
    self.value = value
    self.dateStyle = dateStyle
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // Below `textRenderer(_:)`, the renderer draws the text (`TextRenderer.swift`).
    let renderer = context.environment._textRenderer
    if renderer != nil || context.environment._publishesTextLayout { return _renderMeasured(drawnBy: renderer, in: context) }
    return _renderPlain(in: context)
  }

  @MainActor func _renderPlain(in context: _RenderContext) -> _RenderNode {
    if !_textRuns.isEmpty { return _renderRuns(in: context) }
    if let inline = _inlineImage { return inline._render() }
    let node = _RenderNode.text(_shownValue(in: context))
    // A redacted date is a placeholder too: the date the host would format never reaches the page.
    if let dateStyle, !_isRedacted(in: context) { node.attributes["data-text-date-style"] = dateStyle.rawValue }
    _applyTextStyles(to: node)
    // The date a date text carries for the host (its epoch, its range) goes too.
    if _isRedacted(in: context) { for name in node.attributes.keys where name.hasPrefix("data-text-date") { node.attributes.removeValue(forKey: name) } }
    _applyLineLimit(context.environment.lineLimit, to: node)
    return node
  }

  /// Whether this text is drawn as a placeholder: the placeholder reason, or the privacy reason in a `privacySensitive()`
  /// view.
  @MainActor func _isRedacted(in context: _RenderContext) -> Bool {
    let reasons = context.environment.redactionReasons
    return reasons.contains(.placeholder) || (reasons.contains(.privacy) && context.environment._isPrivacySensitive)
  }

  /// The string the page gets. Under the placeholder redaction reason (or the privacy reason, inside a
  /// `privacySensitive()` view) SwiftUI draws placeholder shapes, so the text is replaced by figure spaces of the same
  /// length (line breaks kept): the real string never reaches the DOM. A date style keeps its value, which the host
  /// formats; a redacted date is a placeholder of a date's usual width.
  @MainActor func _shownValue(in context: _RenderContext) -> String {
    guard _isRedacted(in: context) else { return value }
    if dateStyle != nil { return String(repeating: "\u{2007}", count: 10) }
    let mark: Character = "\u{2007}"
    var shown = ""
    for character in value { shown.append(character == "\n" ? character : mark) }
    return shown
  }
}

extension Text {
  /// Splits a resolved string at the image markers `appendInterpolation(_: Image)` left, so the images become runs.
  mutating func _expandInlineImages() {
    let marker: Character = "\u{FFFC}"
    guard value.contains(marker) else { return }
    var runs: [Text] = []
    var literal = ""
    var index = value.startIndex
    while index < value.endIndex {
      if value[index] == marker, let close = value[value.index(after: index)...].firstIndex(of: marker) {
        if !literal.isEmpty { runs.append(Text(verbatim: literal)); literal = "" }
        runs.append(Text._imageRun(source: String(value[value.index(after: index)..<close]), alt: ""))
        index = value.index(after: close)
      } else {
        literal.append(value[index])
        index = value.index(after: index)
      }
    }
    if !literal.isEmpty { runs.append(Text(verbatim: literal)) }
    let plain = runs.map { $0.value }.joined()
    value = plain
    _textRuns = runs
  }

  /// The run `Text(Image(source, alt:))` is. `Image` is a View, so its initializers are main-actor; the
  /// nonisolated initializers that split marker strings build the run here instead.
  static func _imageRun(source: String, alt: String) -> Text {
    // A symbol has no bitmap in the browser: it is its glyph, drawn as text.
    if source.hasPrefix("symbol:") { return Text(verbatim: _systemSymbolGlyph(String(source.dropFirst(7)))) }
    var run = Text(verbatim: "")
    run._inlineImage = _InlineImage(source: source, alt: alt, size: nil, baselineOffset: -3)
    return run
  }
}

/// An image set in a line of text: scaled to a height, lowered onto the baseline.
struct _InlineImage {
  var source: String
  var alt: String
  /// Height in points; nil is one line of the surrounding font (`1em`).
  var size: Double?
  var baselineOffset: Double

  @MainActor func _render() -> _RenderNode {
    let node = _RenderNode.element("img")
    node.classes = ["inline-image"]
    if let source = _ImageAssets.source(forMarked: source) { node.attributes["src"] = source }
    node.attributes["alt"] = alt
    node.attributes["draggable"] = "false"
    node.styles["height"] = size.map { "\(Int($0.rounded()))px" } ?? "1em"
    node.styles["width"] = "auto"
    node.styles["display"] = "inline-block"
    node.styles["vertical-align"] = "\(-baselineOffset)px"
    return node
  }
}

extension Text {
  /// `Text(Image("name"))`: the image becomes a run of the line, so it flows and wraps with the words around it.
  public init(_ image: Image) {
    self = Text._imageRun(source: _ImageAssets.marked(image.source, allowsRemote: image.allowsRemoteSource), alt: image.alt ?? "")
  }

  /// An image run with an explicit size and baseline offset (rich text with custom emoji).
  @_spi(Renderer) public init(_inlineImageSource source: String, alt: String, size: Double?, baselineOffset: Double) {
    self.init(verbatim: alt)
    _inlineImage = _InlineImage(source: source, alt: alt, size: size, baselineOffset: baselineOffset)
  }
}

extension Text.DateStyle {
  var rawValue: String {
    switch self {
    case .date: return "date"
    case .time: return "time"
    case .relative: return "relative"
    case .offset: return "offset"
    case .timer: return "timer"
    }
  }
}

/// Sendable is declared here, with the stored `snapshot`, so the `Transferable` conformance in DragDrop.swift (which
/// requires it) can live in its own file. The snapshot is a view tree built on the main actor and never mutated after,
/// so crossing actors only shares an immutable value.
public struct Image: @unchecked Sendable {
  public typealias Body = Never
  package let source: String
  package let alt: String?
  private let systemName: String?
  /// Set by the framework's `Image(_:alt:)`, which takes a URL; Apple's `Image(_:bundle:)` names an asset or a file.
  package var allowsRemoteSource = false
  /// A rendered view standing in for a bitmap (see `ImageRenderer`).
  package var snapshot: AnyView?
  /// What SwiftUI's `Image -> Image` modifiers (`resizable`, `interpolation`) set on the image element itself.
  var imageAttributes: _NodeValues = [:]
  var imageStyles: _NodeValues = [:]
  package init(_ source: String, alt: String?) { self.source = source; self.alt = alt; systemName = nil; allowsRemoteSource = true }
  public init(_ source: String, bundle: Bundle? = nil) { self.source = source; self.alt = source; systemName = nil }
  public init(systemName: String) { source = "symbol:\(systemName)"; alt = systemName; self.systemName = systemName }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = renderElement(in: context)
    for (name, value) in imageAttributes { node.attributes[name] = value }
    for (name, value) in imageStyles { node.styles[name] = value }
    return node
  }
  @MainActor private func renderElement(in context: _RenderContext) -> _RenderNode {
    if let snapshot {
      let node = _RenderNode.element("div")
      node.classes = ["image-snapshot"]
      node.styles["display"] = "flex"
      node.styles["align-items"] = "center"
      node.styles["justify-content"] = "center"
      node.children = [snapshot._render(in: context)]
      return node
    }
    if let systemName {
      // SF Symbols are not available in a browser. Render a local, accessible
      // symbol primitive instead of emitting the old `symbol:` pseudo-URL,
      // which browsers treat as a broken image. The browser adapter upgrades
      // known names to Lucide SVGs after commit; this glyph table remains a
      // deterministic fallback for unknown symbols and non-browser hosts.
      let node = _RenderNode.element("span")
      node.classes = ["symbol-icon"]
      node.attributes["data-symbol"] = systemName
      node.attributes["role"] = "img"
      _AccessibilityBackend.setLabel(alt ?? systemName, on: node)
      node.children = [.text(_systemSymbolGlyph(systemName))]
      return node
    }
    // An asset-catalog name resolves to the file the build copied into the
    // bundle (`_ImageAssets`); anything else is a path or URL used as is.
    let source = _ImageAssets.source(for: self.source, allowsRemote: allowsRemoteSource) ?? ""
    if source.hasSuffix(".symbol.svg") {
      // A custom SF Symbol from the asset catalog: a mask over the current text color, as symbols are tinted.
      let node = _RenderNode.element("span")
      node.classes = ["symbol-icon", "custom-symbol"]
      node.attributes["role"] = "img"
      _AccessibilityBackend.setLabel(alt ?? self.source, on: node)
      node.styles["display"] = "inline-block"
      node.styles["width"] = "1.4em"
      node.styles["height"] = "1.4em"
      node.styles["background-color"] = "currentColor"
      node.styles["-webkit-mask"] = "\(_cssQuotedURL(source)) center / contain no-repeat"
      node.styles["mask"] = "\(_cssQuotedURL(source)) center / contain no-repeat"
      return node
    }
    let node = _RenderNode.element("img"); node.classes = ["picture-view"]
    if !source.isEmpty { node.attributes["src"] = source }
    // Let the browser schedule ordinary media without blocking first paint.
    // Relative/local resources benefit from the same hints as remote URLs in
    // feed-style applications. Data/blob URLs are already resident in the
    // document and should remain eager because deferring them adds no useful
    // network work and can delay tiny inline assets.
    if !source.hasPrefix("data:") && !source.hasPrefix("blob:") {
      node.attributes["loading"] = "lazy"
      node.attributes["decoding"] = "async"
    }
    if let alt { node.attributes["alt"] = alt }; return node
  }
}
extension Image: View {}

/// A browser-backed asynchronous image.  The browser performs the actual
/// fetch; Fiber owns the phase and re-renders through the normal load/error
/// event path.  This keeps the public API SwiftUI-shaped without introducing
/// URLSession or JavaScript types into Core.
package struct AsyncImageError: Error, Hashable, Sendable {
  package let message: String
  package init(_ message: String) { self.message = message }
}

public enum AsyncImagePhase {
  case empty
  case success(Image)
  case failure(any Error)

  public var image: Image? {
    if case .success(let image) = self { return image }
    return nil
  }

  public var error: (any Error)? {
    if case .failure(let error) = self { return error }
    return nil
  }
}

public nonisolated struct AsyncImage<Content: View>: View {
  public typealias Body = Never
  package let url: URL?
  package let scale: Double
  private let content: (AsyncImagePhase) -> Content
  @State(memberID: 3649057272) private var phase: AsyncImagePhase = .empty
  @State(memberID: 3649057273) private var phaseSource: String? = nil

  nonisolated public init(
    url: URL?,
    scale: Double = 1,
    @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
  ) {
    self.url = url
    self.scale = scale
    self.content = content
  }

  /// SwiftUI's no-content convenience keeps the most common spelling small;
  /// the result is type-erased only at this convenience boundary.
 nonisolated public init(url: URL?, scale: Double = 1) where Content == AnyView {
    let content: (AsyncImagePhase) -> AnyView = { phase in
      if let image = phase.image {
        return AnyView(image)
      } else if phase.error != nil {
        return AnyView(EmptyView())
      } else {
        return AnyView(ProgressView())
      }
    }
    self.init(url: url, scale: scale, content: content)
  }

  /// SwiftUI's most common AsyncImage spelling supplies separate success and
  /// placeholder builders.  The success builder receives the loaded `Image`
  /// (rather than an `AsyncImagePhase`); erase only this convenience boundary
  /// so project code can keep the familiar `image.resizable()` syntax.
 nonisolated public init<ImageContent: View, Placeholder: View>(
    url: URL?,
    scale: Double = 1,
    @ViewBuilder content: @escaping (Image) -> ImageContent,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) where Content == AnyView {
    self.url = url
    self.scale = scale
    self.content = { phase in
      switch phase {
      case .success(let image): return AnyView(content(image))
      case .empty, .failure: return AnyView(placeholder())
      }
    }
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    guard let url else {
      return content(.failure(AsyncImageError("Missing image URL")))._render(in: context)
    }

    let source = url.absoluteString
    // AsyncImage may keep the same Fiber identity while its input URL changes.
    // A phase belongs to the request that produced it, never to every later
    // URL supplied to this view.
    let storedPhase = phase
    let currentPhase = phaseSource == source ? storedPhase : .empty
    switch currentPhase {
    case .success:
      return content(currentPhase)._render(in: context.child(_FiberKey("content")))
    case .failure:
      return content(currentPhase)._render(in: context.child(_FiberKey("content")))
    case .empty:
      let visible = content(.empty)._render(in: context.child(_FiberKey("content")))
      let preload = _RenderNode.element("img")
      preload.classes = ["async-image-loader"]
      preload.attributes["src"] = source
      preload.attributes["loading"] = "lazy"
      preload.attributes["decoding"] = "async"
      preload.attributes["data-scale"] = _asyncImageScale(scale)
      // Image loading is not an interaction controlled by the inherited
      // `isEnabled` environment. A disabled ancestor must not prevent the
      // browser from settling an AsyncImage phase; doing so would leave the
      // view permanently on its placeholder. The phase events are internal
      // lifecycle events and remain safe to register for every image.
      preload.events["load"] = _EventHandler(name: "load", action: {
        phaseSource = source
        // The image the URL loaded: a remote source is what `AsyncImage` is for, unlike a name given to `Image(_:)`.
        phase = .success(Image(source, alt: source))
      })
      preload.events["error"] = _EventHandler(name: "error", action: {
        phaseSource = source
        phase = .failure(AsyncImageError("Unable to load image"))
      })
      let wrapper = _RenderNode.element("div")
      wrapper.classes = ["async-image"]
      wrapper.attributes["data-async-image"] = "true"
      wrapper.children = [visible, preload].filter { !$0.isEmpty }
      return wrapper
    }
  }
}

private func _asyncImageScale(_ scale: Double) -> String {
  // A scale that is not a positive finite number is not a display scale: Apple renders it at 1. A huge finite one is
  // capped before it is converted to an integer, which traps past Int64.
  guard scale.isFinite, scale > 0 else { return "1" }
  let scale = Swift.min(scale, 1_000_000)
  return scale.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(scale)) : String(scale)
}

func _systemSymbolGlyph(_ name: String) -> String {
  switch name {
  case "checkmark": return "✓"
  case "xmark", "multiply": return "×"
  case "plus": return "+"
  case "minus": return "−"
  case "chevron.left", "chevron.left.circle", "chevron.left.circle.fill": return "‹"
  case "chevron.right", "chevron.right.circle", "chevron.right.circle.fill": return "›"
  case "chevron.up", "chevron.up.circle", "chevron.up.circle.fill": return "⌃"
  case "chevron.down", "chevron.down.circle", "chevron.down.circle.fill": return "⌄"
  case "arrow.left", "arrow.left.circle", "arrow.left.circle.fill": return "←"
  case "arrow.right", "arrow.right.circle", "arrow.right.circle.fill": return "→"
  case "arrow.up", "arrow.up.circle", "arrow.up.circle.fill": return "↑"
  case "arrow.down", "arrow.down.circle", "arrow.down.circle.fill": return "↓"
  case "magnifyingglass", "magnifyingglass.circle", "magnifyingglass.circle.fill": return "⌕"
  case "gear", "gear.fill", "gearshape", "gearshape.fill": return "⚙"
  case "star", "star.fill": return "★"
  case "heart", "heart.fill": return "♥"
  case "person", "person.fill", "person.crop.circle", "person.crop.circle.fill": return "●"
  case "house", "house.fill": return "⌂"
  case "trash", "trash.fill": return "♲"
  case "calendar", "calendar.circle": return "▣"
  case "lock", "lock.fill": return "🔒"
  case "eye", "eye.fill": return "◉"
  case "sparkles": return "✦"
  default: return "•"
  }
}

public nonisolated struct VStack<Content: View>: View {
  public typealias Body = Never
  package let alignment: HorizontalAlignment
  package let spacing: Double?
  package let content: Content
  public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) { self.alignment = alignment; self.spacing = spacing; self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    if context._endsLazyScope(keeping: .vertical) { return _renderEndingLazyScope(self, in: context) }
    // The node is built before and closed after the nested render in functions of their own: a container sits on
    // the render recursion at every level, and this frame stays on the stack while its content renders.
    let node = _stackNode(vertical: true, alignment: alignment.cssValue, spacing: spacing)
    // A deep render hands the content to the loop that drives the pass (see `_RenderStaging`).
    if _RenderStaging.wantsDeferral {
      _deferStackChild(content, context: context, to: node)
      return node
    }
    let child = content._render(in: context)
    _attachStackChild(child, to: node)
    return node
  }
}

public nonisolated struct HStack<Content: View>: View {
  public typealias Body = Never
  package let alignment: VerticalAlignment
  package let spacing: Double?
  package let content: Content
  public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) { self.alignment = alignment; self.spacing = spacing; self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    if context._endsLazyScope(keeping: .horizontal) { return _renderEndingLazyScope(self, in: context) }
    let node = _stackNode(vertical: false, alignment: alignment.cssValue, spacing: spacing)
    // The flexible-width mark is derived from the content, which a deep render hands to the loop that drives the
    // pass: it is set when the content has rendered, and reading the node's attributes renders it first.
    if _RenderStaging.wantsDeferral {
      _deferChild(content, context: context, to: node, completion: .flexibleWidth)
      return node
    }
    let child = content._render(in: context)
    _attachStackChild(child, to: node)
    // With renders waiting in the loop, looking through the child would run them from here.
    if _RenderStaging.hasPending {
      _postponeCompletion(.flexibleWidth, of: node, child: child)
    } else if _hasFlexibleSpacer(in: child) {
      node.attributes["data-flexible-width"] = "true"
    }
    return node
  }
}

/// The element a `VStack` or `HStack` renders, before its content. Out of line (see `VStack._render`).
@inline(never)
@MainActor private func _stackNode(vertical: Bool, alignment: String, spacing: Double?) -> _RenderNode {
  let node = _RenderNode.element("div")
  node.classes = [vertical ? "vstack" : "hstack"]
  node.attributes["data-layout-kind"] = vertical ? "vstack" : "hstack"
  node.attributes["data-layout-alignment"] = alignment
  node.styles["align-items"] = alignment
  if let spacing { node.attributes["data-layout-gap"] = String(spacing); node.styles["gap"] = "\(spacing.clean)px" }
  return node
}

@inline(never)
@MainActor private func _attachStackChild(_ child: _RenderNode, to node: _RenderNode) {
  // A child that stands in for a render that has not run is not known to be empty yet: looking would render it from
  // here, on top of the container's frames, so the container keeps it for the loop that drives the pass.
  if child._isPendingRender {
    _deferBuiltChildren(of: node, after: child) { child.isEmpty ? [] : [child] }
    return
  }
  node.children = child.isEmpty ? [] : [child]
}

public nonisolated struct LazyVStack<Content: View>: View {
  public typealias Body = Never
  let stack: VStack<Content>
  public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) { stack = VStack(alignment: alignment, spacing: spacing, content: content) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    var lazyContext = context
    lazyContext.lazyAxis = .vertical
    lazyContext.lazyCollectionsForceDeferred = true
    lazyContext.lazyLaneCount = 1
    let node = stack._render(in: lazyContext)
    node.classes.append("lazy-vstack")
    node.attributes["data-lazy"] = "vertical"
    return node
  }
}

public nonisolated struct LazyHStack<Content: View>: View {
  public typealias Body = Never
  let stack: HStack<Content>
  public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) { stack = HStack(alignment: alignment, spacing: spacing, content: content) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    var lazyContext = context
    lazyContext.lazyAxis = .horizontal
    lazyContext.lazyCollectionsForceDeferred = true
    lazyContext.lazyLaneCount = 1
    let node = stack._render(in: lazyContext)
    node.classes.append("lazy-hstack")
    node.attributes["data-lazy"] = "horizontal"
    return node
  }
}

public nonisolated struct ZStack<Content: View>: View {
  public typealias Body = Never
  package let alignment: Alignment
  package let content: Content
  public nonisolated init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) { self.alignment = alignment; self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    if context._endsLazyScope() { return _renderEndingLazyScope(self, in: context) }
    let node = _zstackNode(alignment: alignment)
    if _RenderStaging.wantsDeferral {
      _deferStackChild(content, context: context, to: node)
      return node
    }
    let child = content._render(in: context)
    _attachStackChild(child, to: node)
    return node
  }
}

@inline(never)
@MainActor private func _zstackNode(alignment: Alignment) -> _RenderNode {
  let node = _RenderNode.element("div"); node.classes = ["zstack"]; node.attributes["data-layout-kind"] = "zstack"; for (key, value) in _semanticAlignment(alignment) { node.attributes[key] = value }; node.attributes["data-layout-alignment"] = alignment.cssValue; node.styles["place-items"] = alignment.cssValue
  return node
}

public struct Spacer {
  public typealias Body = Never
  public let minLength: Double?
  public init(minLength: Double? = nil) { self.minLength = minLength }
  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["flex-spacer"]
    node.attributes["data-layout-kind"] = "spacer"
    if let minLength { node.attributes["data-spacer-min"] = String(minLength) }
    if let minLength { node.styles["--spacer-min-length"] = "\(minLength.clean)px" }
    return node
  }
}
extension Spacer: View {}

/// Whether `node` is a frame that fixes its width: one the search for a `Spacer` does not go through, because the spacer
/// below it has no width to take from the stack. An element can stand for a chain of frames and padding
/// (`_SemanticLayers`); a frame anywhere in the chain stops the search, as the wrapper elements did.
func _frameFixesWidth(_ node: _RenderNode) -> Bool {
  guard node.classes.contains("frame-box") else { return false }
  func fixes(_ width: String?, _ maxWidth: String?) -> Bool {
    if let width, width != "inf" { return true }
    if let maxWidth, maxWidth != "inf" { return true }
    return false
  }
  if fixes(node.attributes["data-frame-w"], node.attributes["data-frame-max-w"]) { return true }
  for layer in _SemanticLayers.innerLayers(of: node) where layer.kind == "frame" {
    if fixes(layer.value("frame-w"), layer.value("frame-max-w")) { return true }
  }
  return false
}

/// Detects `Spacer` usage in the current horizontal stack without borrowing a
/// spacer from a nested stack, control label, or a frame that fixes its width.
/// Walks the nodes below with a stack of its own: a tree that is deep for the render is deep for this too.
func _hasFlexibleSpacer(in root: _RenderNode) -> Bool {
  var pending = [root]
  while let node = pending.popLast() {
    if node.classes.contains("flex-spacer") { return true }

    if _frameFixesWidth(node) { continue }

    let isLayoutBoundary = node.classes.contains("hstack") ||
      node.classes.contains("vstack") ||
      node.classes.contains("push-button") ||
      node.classes.contains("anchor-link") ||
      node.classes.contains("navigation-link") ||
      node.classes.contains("toggle-switch")
    if isLayoutBoundary { continue }
    // Pushed last first, so the nodes are visited in the order of the recursion this replaces.
    for child in node.children.reversed() { pending.append(child) }
  }
  return false
}

/// Detects whether a label contains a horizontal `Spacer` and marks its
/// interactive control so the browser host can carry the flexible proposal
/// through its wrappers.
func _markFlexibleWidthControl(_ label: _RenderNode, control: _RenderNode) {
  // A loop with an explicit stack: a label built from data can nest arbitrarily deep.
  func containsHorizontalSpacer(_ root: _RenderNode) -> Bool {
    var stack: [(node: _RenderNode, inHorizontalStack: Bool)] = [(root, false)]
    while let entry = stack.popLast() {
      let node = entry.node
      if node.classes.contains("flex-spacer") {
        if entry.inHorizontalStack { return true }
        continue
      }
      if _frameFixesWidth(node) { continue }

      let childAxis: Bool
      if node.classes.contains("hstack") { childAxis = true }
      else if node.classes.contains("vstack") { childAxis = false }
      else { childAxis = entry.inHorizontalStack }

      for child in node.children { stack.append((child, childAxis)) }
    }
    return false
  }

  if containsHorizontalSpacer(label) {
    control.attributes["data-flexible-width"] = "true"
  }
}

public nonisolated struct Divider: View {
  public typealias Body = Never
  public nonisolated init() {}
  public func _render(in context: _RenderContext) -> _RenderNode {
    _RenderNode.element("hr")
  }
}

public nonisolated struct Button<Label: View>: View {
  public typealias Body = Never
  package let action: @MainActor () -> Void
  package let label: Label
  package let role: ButtonRole?
  /// Set by `Button(_: PrimitiveButtonStyleConfiguration)`.
  var _isPrimitiveConfiguration = false
  @preconcurrency public nonisolated init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label(); role = nil }
  @preconcurrency public nonisolated init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label(); self.role = role }
  @_disfavoredOverload @preconcurrency public nonisolated init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) where Label == Text { self.init(action: action) { Text(String(title)) } }
  @preconcurrency public nonisolated init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) where Label == Text { self.init(titleKey.resolved, action: action) }
  @_disfavoredOverload @preconcurrency public nonisolated init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) where Label == Text { self.init(role: role, action: action) { Text(title) } }
  @preconcurrency public nonisolated init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) where Label == Text { self.init(titleKey.resolved, role: role, action: action) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    if _isPrimitiveConfiguration { return _renderPrimitiveConfigurationButton(label: label, action: action, context: context) }
    let node = _buttonNode(role: role, action: action, context: context)
    let child = _renderButtonLabel(label, role: role, action: action, node: node, context: context)
    _finishButtonNode(node, label: child)
    return node
  }
}

/// The label of `Button(_:systemImage:action:)`: the title with its symbol, as `Label(_:systemImage:)` draws it.
nonisolated private func _systemImageButtonLabel(_ title: String, systemImage name: String) -> Label<Text, Image> {
  Label<Text, Image>(title, systemImage: name)
}

/// SwiftUI's `Button` initializers that take a title and an SF Symbol: `Button("Restart", systemImage: "arrow.counterclockwise") { ... }`.
public extension Button where Label == SwiftUIWebCore.Label<Text, Image> {
  @_disfavoredOverload nonisolated init<S: StringProtocol>(_ title: S, systemImage name: String, action: @escaping @MainActor () -> Void) {
    self.init(action: action) { _systemImageButtonLabel(String(title), systemImage: name) }
  }
  nonisolated init(_ titleKey: LocalizedStringKey, systemImage name: String, action: @escaping @MainActor () -> Void) {
    self.init(titleKey.resolved, systemImage: name, action: action)
  }
  @_disfavoredOverload nonisolated init<S: StringProtocol>(_ title: S, systemImage name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
    self.init(role: role, action: action) { _systemImageButtonLabel(String(title), systemImage: name) }
  }
  nonisolated init(_ titleKey: LocalizedStringKey, systemImage name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
    self.init(titleKey.resolved, systemImage: name, role: role, action: action)
  }
}

/// The `<button>` of `Button._render` before its label, out of the generic type so it is compiled once rather than once
/// per label type.
@MainActor private func _buttonNode(role: ButtonRole?, action: @escaping @MainActor () -> Void, context: _RenderContext) -> _RenderNode {
  let node = _RenderNode.element("button")
  node.attributes["type"] = "button"
  node.attributes["data-control-kind"] = "button"
  // A custom ButtonStyle owns the visual body returned from
  // `makeBody(configuration:)`. Keep the native button semantics on the
  // outer element, but reset the default design-system shell so a style
  // such as `BlueButton` is not wrapped in an unexpected blue button.
  let styleClass = context.environment.buttonStyleIsCustom
    ? "button-custom"
    : "button-\(context.environment.buttonStyle.rawValue)"
  node.classes = ["push-button", styleClass, "control-\(context.environment.controlSize.rawValue)"]
  node.attributes["data-button-style"] = context.environment.buttonStyle.rawValue
  if context.environment.buttonStyleIsCustom { node.attributes["data-button-style-custom"] = "true" }
  node.attributes["data-control-size"] = context.environment.controlSize.rawValue
  if let tint = context.environment.tint {
    node.attributes["data-tint"] = tint.cssValue
    node.styles["--tint-color"] = tint.cssValue
  }
  if let role { node.attributes["data-role"] = role.rawValue }
  if context.environment.isEnabled { node.events["click"] = _EventHandler(name: "click", action: action) }
  else { node.attributes["disabled"] = "disabled"; node.attributes["aria-disabled"] = "true" }
  _applyKeyboardShortcut(context, to: node)
  return node
}

/// Gives `Button._render`'s node its rendered label.
@MainActor private func _finishButtonNode(_ node: _RenderNode, label child: _RenderNode) {
  _markFlexibleWidthControl(child, control: node)
  _applyButtonVisibleShape(child, to: node)
  node.children = child.isEmpty ? [] : [child]
}

@MainActor @preconcurrency public struct Link<Label: View>: View {
  public typealias Body = Never
  package let destination: URL
  nonisolated(unsafe) package let label: Label
  @MainActor @preconcurrency public init(destination: URL, @ViewBuilder label: () -> Label) { self.destination = destination; self.label = label() }
  @_disfavoredOverload nonisolated public init<S: StringProtocol>(_ title: S, destination: URL) where Label == Text { self.destination = destination; self.label = Text(String(title)) }
  nonisolated public init(_ titleKey: LocalizedStringKey, destination: URL) where Label == Text { self.destination = destination; self.label = Text(titleKey.resolved) }
  public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("a")
    node.classes = ["anchor-link", "control-\(context.environment.controlSize.rawValue)"]
    node.attributes["data-control-kind"] = "link"
    node.attributes["data-control-size"] = context.environment.controlSize.rawValue
    if let href = _safeURLAttribute(destination.absoluteString) { node.attributes["href"] = href }
    if let tint = context.environment.tint {
      node.attributes["data-tint"] = tint.cssValue
      node.styles["--tint-color"] = tint.cssValue
    }
    let child = label._render(in: context)
    _markFlexibleWidthControl(child, control: node)
    if context.environment[_GroupedListKey.self], !child.isEmpty {
      // In a form a link is a row: laid out as a row, not measured as an opaque box.
      node.classes.append("hstack")
      node.attributes["data-layout-kind"] = "hstack"
      node.attributes["data-layout-schema"] = "1"
      node.attributes["data-layout-gap"] = _semanticNumber(0)
      node.attributes["data-align-x"] = "0.5"
      node.attributes["data-align-y"] = "0.5"
    }
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public enum ButtonRole: Sendable { case destructive, cancel 
  /// The CSS spelling of each case; SwiftUI does not expose a raw value.
  var rawValue: String {
    switch self {
    case .destructive: "destructive"
    case .cancel: "cancel"
    }
  }
}

public nonisolated struct TextField: View {
  public typealias Body = Never
  package let title: String
  package let text: Binding<String>
  package let axis: Axis
  private let prompt: String?
  private let onEditingChanged: ((Bool) -> Void)?
  private let onCommit: (() -> Void)?
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>) { self.init(String(title), text: text, axis: .horizontal, prompt: nil, onEditingChanged: nil, onCommit: nil) }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>) { self.init(titleKey.resolved, text: text) }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) { self.init(String(title), text: text, axis: axis, prompt: nil, onEditingChanged: nil, onCommit: nil) }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) { self.init(titleKey.resolved, text: text, axis: axis) }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis = .horizontal) {
    self.init(String(title), text: text, axis: axis, prompt: prompt?.value, onEditingChanged: nil, onCommit: nil)
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis = .horizontal) { self.init(titleKey.resolved, text: text, prompt: prompt, axis: axis) }
  /// The label names the field for accessibility; SwiftUI's label view is not drawn inside a text field.
  public nonisolated init<Label: View>(text: Binding<String>, prompt: Text? = nil, axis: Axis, @ViewBuilder label: () -> Label) {
    self.init("", text: text, axis: axis, prompt: prompt?.value, onEditingChanged: nil, onCommit: nil)
  }
  public nonisolated init<Label: View>(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
    self.init("", text: text, axis: .horizontal, prompt: prompt?.value, onEditingChanged: nil, onCommit: nil)
  }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void = {}) {
    self.init(String(title), text: text, axis: .horizontal, prompt: nil, onEditingChanged: onEditingChanged, onCommit: onCommit)
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onCommit: @escaping () -> Void = {}) { self.init(titleKey.resolved, text: text, onEditingChanged: onEditingChanged, onCommit: onCommit) }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) {
    self.init(String(title), text: text, axis: .horizontal, prompt: nil, onEditingChanged: nil, onCommit: onCommit)
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) { self.init(titleKey.resolved, text: text, onCommit: onCommit) }
  private init(_ title: String, text: Binding<String>, axis: Axis, prompt: String?, onEditingChanged: ((Bool) -> Void)?, onCommit: (() -> Void)?) {
    self.title = title; self.text = text; self.axis = axis; self.prompt = prompt; self.onEditingChanged = onEditingChanged; self.onCommit = onCommit
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let isMultiline = axis == .vertical
    let node = _RenderNode.element(isMultiline ? "textarea" : "input")
    node.classes = [isMultiline ? "text-area" : "field-input"]
    node.attributes["data-control-kind"] = isMultiline ? "text-field-multiline" : "text-field"
    if !isMultiline { node.attributes["type"] = "text" }
    node.attributes["placeholder"] = prompt ?? title
    _AccessibilityBackend.setLabel(title.isEmpty ? (prompt ?? "Text field") : title, on: node)
    if isMultiline { node.children = [.text(text.wrappedValue)] }
    else { node.attributes["value"] = text.wrappedValue }
    if let sourceID = text._sourceID {
      node.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .property("value"),
        value: { text.wrappedValue }
      ))
    }
    if isMultiline { node.attributes["data-axis"] = "vertical"; context.environment._applyFieldLineLimit(to: node) }
    // `.textFieldStyle(.plain)` removes every framework-owned chrome so an
    // application can draw its own field with ordinary SwiftUI modifiers.
    if context.environment._textFieldStyle == "plain" { node.attributes["data-field-chrome"] = "plain" }
    if context.environment.isEnabled {
      node.events["input"] = _EventHandler(name: "input", action: { self.text.wrappedValue = $0 })
      node.events["focus"] = _EventHandler(name: "focus", action: { self.onEditingChanged?(true) })
      node.events["blur"] = _EventHandler(name: "blur", action: { self.onEditingChanged?(false) })
      // Only a field with `onCommit` takes Return itself: without one, the `.onSubmit` of a view around it does.
      if onCommit != nil { node.events["submit"] = _EventHandler(name: "submit", action: { self.onCommit?() }, preventsDefault: true) }
    } else {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    return node
  }
}

public nonisolated struct SecureField: View {
  public typealias Body = Never
  package let title: String
  package let text: Binding<String>
  private let prompt: String?
  private let onCommit: (() -> Void)?
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>) { self.title = String(title); self.text = text; self.prompt = nil; self.onCommit = nil }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>) { self.init(titleKey.resolved, text: text) }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) { self.init(titleKey.resolved, text: text, prompt: prompt) }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) { self.title = String(title); self.text = text; self.prompt = prompt?.value; self.onCommit = nil }
  public nonisolated init<Label: View>(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) { self.title = ""; self.text = text; self.prompt = prompt?.value; self.onCommit = nil }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, onCommit: @escaping () -> Void) { self.title = String(title); self.text = text; self.prompt = nil; self.onCommit = onCommit }
  public nonisolated init(_ titleKey: LocalizedStringKey, text: Binding<String>, onCommit: @escaping () -> Void) { self.init(titleKey.resolved, text: text, onCommit: onCommit) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("input")
    node.classes = ["field-input"]
    node.attributes["data-control-kind"] = "secure-field"
    node.attributes["type"] = "password"
    node.attributes["placeholder"] = prompt ?? title
    _AccessibilityBackend.setLabel(title.isEmpty ? (prompt ?? "Secure field") : title, on: node)
    // Never serialize a credential into HTML/_RenderNode attributes. The
    // Embedded browser hydrates the live `value` property through its
    // short-lived WASM host channel after the element is mounted.
    node._secureValue = { self.text.wrappedValue }
    if context.environment._textFieldStyle == "plain" { node.attributes["data-field-chrome"] = "plain" }
    if let sourceID = text._sourceID {
      node.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .property("value"),
        value: { text.wrappedValue }
      ))
    }
    if context.environment.isEnabled {
      node.events["input"] = _EventHandler(name: "input", action: { self.text.wrappedValue = $0 })
      if onCommit != nil { node.events["submit"] = _EventHandler(name: "submit", action: { self.onCommit?() }, preventsDefault: true) }
    } else {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    return node
  }
}

public nonisolated struct TextEditor: View {
  public typealias Body = Never
  package let text: Binding<String>
  public nonisolated init(text: Binding<String>) { self.text = text }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("textarea")
    node.classes = ["text-area"]
    node.attributes["data-control-kind"] = "text-editor"
    // `.scrollContentBackground(.hidden)` is SwiftUI's opt-out of the editor's
    // system background; on the web it also drops border/padding chrome.
    if context.environment._scrollContentBackgroundHidden { node.attributes["data-field-chrome"] = "plain" }
    _AccessibilityBackend.setLabel("Text editor", on: node)
    node.children = [.text(text.wrappedValue)]
    if let sourceID = text._sourceID {
      node.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .property("value"),
        value: { text.wrappedValue }
      ))
    }
    if context.environment.isEnabled {
      node.events["input"] = _EventHandler(name: "input", action: { self.text.wrappedValue = $0 })
    } else {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    return node
  }
}

public nonisolated struct Toggle<Label: View>: View {
  public typealias Body = Never
  package let label: Label
  package let isOn: Binding<Bool>
  public nonisolated init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { self.label = label(); self.isOn = isOn }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) where Label == Text { self.label = Text(LocalizedStringKey(String(title)).resolved); self.isOn = isOn }
  public nonisolated init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) where Label == Text { self.init(titleKey.resolved, isOn: isOn) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    var labelContext = context.child(_FiberKey("label"))
    if labelContext.environment._keyboardShortcut != nil { labelContext.environment._keyboardShortcut = nil }
    return _renderToggle(isOn: isOn, labelNode: label._render(in: labelContext), context: context)
  }
}

/// SwiftUI's slider. The browser control works in `Double`: a generic
/// `BinaryFloatingPoint` binding is projected to a `Double` binding that keeps
/// the source identity, so leaf updates and rendering are the same for every
/// value type.
public nonisolated struct Slider<Label: View, ValueLabel: View>: View {
  public typealias Body = Never
  package let value: Binding<Double>
  package let range: ClosedRange<Double>
  /// `0` is a continuous slider. HTML's default step of 1 would round values
  /// such as 0.5 to the maximum for a 0...1 slider, moving the thumb away
  /// from its semantic value.
  package let step: Double
  /// SwiftUI names the control with its label; the browser draws it only as
  /// the accessibility name.
  package let label: Label
  package let minimumValueLabel: ValueLabel
  package let maximumValueLabel: ValueLabel
  package let onEditingChanged: (Bool) -> Void

  private init(
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    label: Label,
    minimumValueLabel: ValueLabel,
    maximumValueLabel: ValueLabel,
    onEditingChanged: @escaping (Bool) -> Void
  ) {
    self.value = value
    self.range = range
    self.step = step
    self.label = label
    self.minimumValueLabel = minimumValueLabel
    self.maximumValueLabel = maximumValueLabel
    self.onEditingChanged = onEditingChanged
  }

  private init<V: BinaryFloatingPoint>(
    _ value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: Double,
    label: Label,
    minimumValueLabel: ValueLabel,
    maximumValueLabel: ValueLabel,
    onEditingChanged: @escaping (Bool) -> Void
  ) {
    self.init(
      value: _sliderProjection(value),
      range: Double(bounds.lowerBound)...Double(bounds.upperBound),
      step: step,
      label: label,
      minimumValueLabel: minimumValueLabel,
      maximumValueLabel: maximumValueLabel,
      onEditingChanged: onEditingChanged
    )
  }

  // MARK: Initializers, in SwiftUI's overload set

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == EmptyView, ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: 0, label: EmptyView(), minimumValueLabel: EmptyView(),
              maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
  }

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == EmptyView, ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: Double(step), label: EmptyView(), minimumValueLabel: EmptyView(),
              maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
  }

  nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: 0, label: label(), minimumValueLabel: EmptyView(),
              maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
  }

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: Double(step), label: label(), minimumValueLabel: EmptyView(),
              maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
  }

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label,
    @ViewBuilder minimumValueLabel: () -> ValueLabel,
    @ViewBuilder maximumValueLabel: () -> ValueLabel,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: 0, label: label(), minimumValueLabel: minimumValueLabel(),
              maximumValueLabel: maximumValueLabel(), onEditingChanged: onEditingChanged)
  }

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    @ViewBuilder label: () -> Label,
    @ViewBuilder minimumValueLabel: () -> ValueLabel,
    @ViewBuilder maximumValueLabel: () -> ValueLabel,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: Double(step), label: label(), minimumValueLabel: minimumValueLabel(),
              maximumValueLabel: maximumValueLabel(), onEditingChanged: onEditingChanged)
  }

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    minimumValueLabel: ValueLabel,
    maximumValueLabel: ValueLabel,
    @ViewBuilder label: () -> Label
  ) where V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: 0, label: label(), minimumValueLabel: minimumValueLabel,
              maximumValueLabel: maximumValueLabel, onEditingChanged: onEditingChanged)
  }

 nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    minimumValueLabel: ValueLabel,
    maximumValueLabel: ValueLabel,
    @ViewBuilder label: () -> Label
  ) where V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: Double(step), label: label(), minimumValueLabel: minimumValueLabel,
              maximumValueLabel: maximumValueLabel, onEditingChanged: onEditingChanged)
  }

 @_disfavoredOverload nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    @ViewBuilder label: () -> Label
  ) where ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: 0, label: label(), minimumValueLabel: EmptyView(),
              maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
  }

 @_disfavoredOverload nonisolated public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    @ViewBuilder label: () -> Label
  ) where ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(value, in: bounds, step: Double(step), label: label(), minimumValueLabel: EmptyView(),
              maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("input")
    node.classes = ["slider-control"]
    node.attributes["data-control-kind"] = "slider"
    node.attributes["type"] = "range"
    node.attributes["min"] = "\(range.lowerBound.clean)"
    node.attributes["max"] = "\(range.upperBound.clean)"
    node.attributes["step"] = step > 0 ? "\(step.clean)" : "any"
    node.attributes["value"] = "\(value.wrappedValue.clean)"
    // Range controls otherwise fall back to the browser's intrinsic width,
    // decoupling their track from the SwiftUI proposal.
    node.styles["display"] = "block"
    node.styles["width"] = "100%"
    node.styles["height"] = "20px"
    _AccessibilityBackend.setNumeric("\(range.lowerBound.clean)", name: "valuemin", on: node)
    _AccessibilityBackend.setNumeric("\(range.upperBound.clean)", name: "valuemax", on: node)
    _AccessibilityBackend.setNumeric("\(value.wrappedValue.clean)", name: "valuenow", on: node)
    let labelText = _toggleAccessibilityText(label._render(in: context.child(_FiberKey("label"))))
    _AccessibilityBackend.setLabel(labelText.flatMap { $0.isEmpty ? nil : $0 } ?? "Value", on: node)
    let span = range.upperBound - range.lowerBound
    if span > 0 {
      let fraction = min(max((value.wrappedValue - range.lowerBound) / span, 0), 1)
      let percent = fraction * 100
      node.styles["--val"] = "\(percent.clean)%"
      node.styles["--slider-value"] = "\(percent.clean)%"
    }
    if let sourceID = value._sourceID {
      node.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .property("value"),
        value: { "\(value.wrappedValue.clean)" }
      ))
      node.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .attribute("aria-valuenow"),
        value: { "\(value.wrappedValue.clean)" }
      ))
      node.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .style("--val"),
        value: {
          let span = range.upperBound - range.lowerBound
          guard span > 0 else { return "" }
          let fraction = min(max((value.wrappedValue - range.lowerBound) / span, 0), 1)
          return "\((fraction * 100).clean)%"
        }
      ))
    }
    if context.environment.isEnabled {
      node.events["input"] = _EventHandler(name: "input", action: {}, valueAction: { raw in
        guard let next = Double(raw), next.isFinite else { return }
        self.value.wrappedValue = min(max(next, self.range.lowerBound), self.range.upperBound)
      })
    } else {
      node.attributes["disabled"] = "disabled"
      node.attributes["aria-disabled"] = "true"
    }
    // SwiftUI places the minimum label before the track and the maximum label
    // after it. Without labels the control stays the bare range input, so the
    // existing DOM contract (and every selector that targets it) is unchanged.
    let minimumNode = minimumValueLabel._render(in: context.child(_FiberKey("minimumValueLabel")))
    let maximumNode = maximumValueLabel._render(in: context.child(_FiberKey("maximumValueLabel")))
    guard minimumNode.kind != .empty || maximumNode.kind != .empty else { return node }
    node.styles["flex"] = "1 1 auto"
    node.styles["min-width"] = "0"
    let group = _RenderNode.element("div")
    group.classes = ["slider-group"]
    group.styles["display"] = "flex"
    group.styles["align-items"] = "center"
    group.styles["gap"] = "8px"
    group.styles["width"] = "100%"
    group.children = [
      _sliderValueLabelNode(minimumNode, className: "slider-minimum-label"),
      node,
      _sliderValueLabelNode(maximumNode, className: "slider-maximum-label"),
    ]
    return group
  }
}

/// Wraps a min/max value label so it keeps its intrinsic width beside the track.
private func _sliderValueLabelNode(_ content: _RenderNode, className: String) -> _RenderNode {
  let node = _RenderNode.element("span")
  node.classes = [className]
  node.styles["flex"] = "0 0 auto"
  node.styles["white-space"] = "nowrap"
  node.children = [content]
  return node
}

/// Projects a floating-point binding to the `Double` the slider edits. The
/// projection keeps the source identity (`_sourceID`), so leaf bindings still
/// patch the control in place.
private func _sliderProjection<V: BinaryFloatingPoint>(_ value: Binding<V>) -> Binding<Double> {
  value.map(get: { Double($0) }, set: { _, next in value.wrappedValue = V(next) })
}

/// Operations a `Stepper` performs on its bound value. Bounded and unbounded
/// steppers share them; the bound only limits how far a step may move.
private struct _StepperOperations {
  let valueText: () -> String
  let increment: @MainActor () -> Void
  let decrement: @MainActor () -> Void
  let canIncrement: () -> Bool
  let canDecrement: () -> Bool
  let minimumText: String?
  let maximumText: String?
}

/// Whether a step of `step` (positive) from `value` stays inside `range` (anywhere, when unbounded). The moved value is
/// never computed, since `advanced(by:)` traps past the type's end; neither is the distance from the value to a bound,
/// which overflows for a range as wide as `Int.min...0`. The standard integers are checked exactly with overflow-reporting
/// arithmetic; another `Strideable` moves the bound back by `step` instead.
///
/// A floating-point value cannot trap when it moves, and moving the bound instead would round differently (0.5 + 0.2 is
/// exactly 0.7, while 0.7 - 0.2 is 0.49999999999999994), so for those types the moved value itself is compared, as SwiftUI
/// compares it.
private func _stepperCanMove<V: Strideable>(_ value: V, by step: V.Stride, up: Bool, in range: ClosedRange<V>?) -> Bool {
  guard step > 0 else { return false }
  if V.self == Double.self || V.self == Float.self {
    guard let range else { return true }
    return range.contains(value.advanced(by: up ? step : -step))
  }
  // The standard integers move with overflow-reporting arithmetic: a move past the type's end is simply unavailable,
  // with or without a range (an unbounded stepper at Int.max is disabled instead of trapping when pressed).
  if let answer = _stepperIntegerCanMove(value, by: step, up: up, range: range) { return answer }
  guard let range else { return true }
  let lower = range.lowerBound, upper = range.upperBound
  if up {
    guard value < upper else { return false }
    let fitsBelowUpper = upper.advanced(by: -step) >= value
    return value >= lower ? fitsBelowUpper : fitsBelowUpper && lower.advanced(by: -step) <= value
  }
  guard value > lower else { return false }
  let fitsAboveLower = lower.advanced(by: step) <= value
  return value <= upper ? fitsAboveLower : fitsAboveLower && upper.advanced(by: step) >= value
}

/// The exact answer for the standard integer types (nil for any other `Strideable`): the moved value is computed with
/// overflow reporting, so neither the value nor a bound can trap near the type's ends.
private func _stepperIntegerCanMove<V: Strideable>(_ value: V, by step: V.Stride, up: Bool, range: ClosedRange<V>?) -> Bool? {
  func bounds<T: FixedWidthInteger>(_: T.Type) -> (T, T) {
    guard let range else { return (T.min, T.max) }
    return (unsafeBitCast(range.lowerBound, to: T.self), unsafeBitCast(range.upperBound, to: T.self))
  }
  func signed<T: FixedWidthInteger>(_: T.Type) -> Bool? {
    guard V.self == T.self, V.Stride.self == T.self else { return nil }
    let (lower, upper) = bounds(T.self)
    return _stepperFixedCanMove(unsafeBitCast(value, to: T.self), by: unsafeBitCast(step, to: T.self), up: up, lower: lower, upper: upper)
  }
  func unsigned<T: FixedWidthInteger>(_: T.Type) -> Bool? {
    guard V.self == T.self, V.Stride.self == Int.self else { return nil }
    // A step past the type's largest value cannot be taken.
    guard let magnitude = T(exactly: unsafeBitCast(step, to: Int.self)) else { return false }
    let (lower, upper) = bounds(T.self)
    return _stepperFixedCanMove(unsafeBitCast(value, to: T.self), by: magnitude, up: up, lower: lower, upper: upper)
  }
  return signed(Int.self) ?? signed(Int64.self) ?? signed(Int32.self) ?? signed(Int16.self) ?? signed(Int8.self)
    ?? unsigned(UInt.self) ?? unsigned(UInt64.self) ?? unsigned(UInt32.self) ?? unsigned(UInt16.self) ?? unsigned(UInt8.self)
}

private func _stepperFixedCanMove<T: FixedWidthInteger>(_ value: T, by step: T, up: Bool, lower: T, upper: T) -> Bool {
  let (next, overflow) = up ? value.addingReportingOverflow(step) : value.subtractingReportingOverflow(step)
  return !overflow && next >= lower && next <= upper
}

private func _stepperOperations<V: Strideable>(
  value: Binding<V>,
  range: ClosedRange<V>?,
  step: V.Stride,
  onEditingChanged: @escaping (Bool) -> Void
) -> _StepperOperations {
  nonisolated(unsafe) let range = range
  nonisolated(unsafe) let step = step
  nonisolated(unsafe) let value = value
  let editingChanged = _mainActor(onEditingChanged)
  // A step that does not move the value in the stepper's direction is refused,
  // as SwiftUI refuses it at the bound.
  return _StepperOperations(
    valueText: { _stepperValueDescription(value.wrappedValue) },
    // The next value is computed from the value that was checked, before the editing callback runs: the callback is
    // the application's and may change the binding, which must not move the step past the bounds (or past Int.max).
    increment: {
      let current = value.wrappedValue
      guard _stepperCanMove(current, by: step, up: true, in: range) else { return }
      let next = current.advanced(by: step)
      editingChanged(true)
      value.wrappedValue = next
      editingChanged(false)
    },
    decrement: {
      let current = value.wrappedValue
      guard _stepperCanMove(current, by: step, up: false, in: range) else { return }
      let next = current.advanced(by: -step)
      editingChanged(true)
      value.wrappedValue = next
      editingChanged(false)
    },
    canIncrement: {
      _stepperCanMove(value.wrappedValue, by: step, up: true, in: range)
    },
    canDecrement: {
      _stepperCanMove(value.wrappedValue, by: step, up: false, in: range)
    },
    minimumText: range.map { _stepperValueDescription($0.lowerBound) },
    maximumText: range.map { _stepperValueDescription($0.upperBound) }
  )
}

/// A SwiftUI-shaped numeric stepper. The view stores operations rather than a
/// type-erased numeric value, so every `Strideable` binding keeps its own
/// source spelling while the rendered control stays compact.
public nonisolated struct Stepper<Label: View>: View {
  public typealias Body = Never
  private let label: Label
  private let valueText: () -> String
  private let increment: @MainActor () -> Void
  private let decrement: @MainActor () -> Void
  private let canIncrement: () -> Bool
  private let canDecrement: () -> Bool
  private let minimumText: String?
  private let maximumText: String?

  private init(label: Label, _ operations: _StepperOperations) {
    self.label = label
    self.valueText = operations.valueText
    self.increment = operations.increment
    self.decrement = operations.decrement
    self.canIncrement = operations.canIncrement
    self.canDecrement = operations.canDecrement
    self.minimumText = operations.minimumText
    self.maximumText = operations.maximumText
  }

  // MARK: Labeled by a view

 @_disfavoredOverload nonisolated public init<V: Strideable>(
    value: Binding<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    @ViewBuilder label: () -> Label
  ) {
    self.init(label: label(), _stepperOperations(value: value, range: nil, step: step, onEditingChanged: onEditingChanged))
  }

 @_disfavoredOverload nonisolated public init<V: Strideable>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    @ViewBuilder label: () -> Label
  ) {
    self.init(label: label(), _stepperOperations(value: value, range: bounds, step: step, onEditingChanged: onEditingChanged))
  }

  /// A `nil` callback disables that button, as in SwiftUI. Each step is reported to `onEditingChanged` as a
  /// complete edit (`true`, then `false`): the browser buttons have no press-and-hold auto-repeat.
 @_disfavoredOverload nonisolated public init(
    onIncrement: (() -> Void)?,
    onDecrement: (() -> Void)?,
    onEditingChanged: @escaping (Bool) -> Void = { _ in },
    @ViewBuilder label: () -> Label
  ) {
    let editingChanged = _mainActor(onEditingChanged)
    let increment = _mainActor(onIncrement), decrement = _mainActor(onDecrement)
    self.init(
      label: label(),
      _StepperOperations(
        valueText: { "" },
        increment: { editingChanged(true); increment?(); editingChanged(false) },
        decrement: { editingChanged(true); decrement?(); editingChanged(false) },
        canIncrement: { increment != nil },
        canDecrement: { decrement != nil },
        minimumText: nil,
        maximumText: nil
      )
    )
  }

  // MARK: Labeled by a title

 @_disfavoredOverload nonisolated public init<S: StringProtocol>(
    _ title: S,
    onIncrement: (() -> Void)?,
    onDecrement: (() -> Void)?,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged) {
      Text(LocalizedStringKey(String(title)).resolved)
    }
  }

  nonisolated public init(
    _ titleKey: LocalizedStringKey,
    onIncrement: (() -> Void)?,
    onDecrement: (() -> Void)?,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(titleKey.resolved, onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged)
  }

 @_disfavoredOverload nonisolated public init<S: StringProtocol, V: Strideable>(
    _ title: S,
    value: Binding<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(label: Text(LocalizedStringKey(String(title)).resolved),
              _stepperOperations(value: value, range: nil, step: step, onEditingChanged: onEditingChanged))
  }

  nonisolated public init<V: Strideable>(
    _ titleKey: LocalizedStringKey,
    value: Binding<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(titleKey.resolved, value: value, step: step, onEditingChanged: onEditingChanged)
  }

 @_disfavoredOverload nonisolated public init<S: StringProtocol, V: Strideable>(
    _ title: S,
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(label: Text(LocalizedStringKey(String(title)).resolved),
              _stepperOperations(value: value, range: bounds, step: step, onEditingChanged: onEditingChanged))
  }

  nonisolated public init<V: Strideable>(
    _ titleKey: LocalizedStringKey,
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(titleKey.resolved, value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["stepper-control"]
    node.attributes["data-control-kind"] = "stepper"
    node.attributes["role"] = "group"
    let labelNode = label._render(in: context.child(_FiberKey("label")))
    if let labelText = _toggleAccessibilityText(labelNode), !labelText.isEmpty { _AccessibilityBackend.setLabel(labelText, on: node) }
    // `.labelsHidden()` keeps the label as the group's accessibility name.
    if !labelNode.isEmpty && !context.environment._labelsHidden { node.children.append(labelNode) }

    let decrementButton = _RenderNode.element("button")
    decrementButton.attributes["type"] = "button"
    _AccessibilityBackend.setLabel("Decrease", on: decrementButton)
    decrementButton.children = [.text("−")]
    if context.environment.isEnabled && canDecrement() {
      decrementButton.events["click"] = _EventHandler(name: "click", action: decrement)
    } else {
      decrementButton.attributes["disabled"] = "disabled"
      decrementButton.attributes["aria-disabled"] = "true"
    }

    let valueNode = _RenderNode.element("span")
    valueNode.attributes["role"] = "spinbutton"
    _AccessibilityBackend.setNumeric(valueText(), name: "valuenow", on: valueNode)
    if let minimumText { _AccessibilityBackend.setNumeric(minimumText, name: "valuemin", on: valueNode) }
    if let maximumText { _AccessibilityBackend.setNumeric(maximumText, name: "valuemax", on: valueNode) }
    // SwiftUI's Stepper draws its label and the two buttons, never its value: the value is for assistive technology, which
    // reads it from the spinbutton's aria-valuenow, and for a label that shows it.
    valueNode.classes = ["stepper-value"]

    let incrementButton = _RenderNode.element("button")
    incrementButton.attributes["type"] = "button"
    _AccessibilityBackend.setLabel("Increase", on: incrementButton)
    incrementButton.children = [.text("+")]
    if context.environment.isEnabled && canIncrement() {
      incrementButton.events["click"] = _EventHandler(name: "click", action: increment)
    } else {
      incrementButton.attributes["disabled"] = "disabled"
      incrementButton.attributes["aria-disabled"] = "true"
    }

    node.children.append(contentsOf: [decrementButton, valueNode, incrementButton])
    return node
  }
}

public nonisolated struct Form<Content: View>: View {
  public typealias Body = Never
  package let content: Content
  public nonisolated init(@ViewBuilder content: () -> Content) { self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("form")
    // The app's accent, kept apart from a row's own tint so grouped rows can colour their icons with it.
    if let tint = context.environment.tint { node.styles["--form-tint-color"] = tint.cssValue }
    // A form owns its vertical scrolling and offers its sections the full width; without a layout role the browser
    // layout treats it as an opaque box and leaves its content to CSS, which centres each section on its own width.
    node.classes = ["form-view", "scroll-view", "scroll-vertical"]
    _ScrollNode(id: _ScrollNode.id(for: context, kind: "form"), axes: .vertical).apply(to: node)
    var groupedContext = context
    groupedContext.environment[_GroupedListKey.self] = true
    // In a form a button with no explicit style reads as tinted text on its row, not as a filled control.
    if groupedContext.environment.buttonStyle == .automatic { groupedContext.environment.buttonStyle = .borderless }
    // The wrapper depends on whether the content is empty, so a deep render builds it where the content renders.
    if _RenderStaging.wantsDeferral {
      let content = self.content
      _deferBuiltChildren(of: node) { Self.wrapped(content._render(in: groupedContext)) }
      return node
    }
    node.children = Self.wrapped(content._render(in: groupedContext))
    return node
  }

  /// The form's children for what its content rendered: nothing for an empty content, otherwise the content inside
  /// the margins and the readable width of a grouped form.
  @MainActor private static func wrapped(_ child: _RenderNode) -> [_RenderNode] {
    if !child.isEmpty {
      // The form's content sits inside the grouped margin SwiftUI gives it, and its sections fill the width.
      let leading = Alignment(horizontal: .leading, vertical: .top)
      let column = _RenderNode.element("div")
      column.classes = ["vstack", "form-content"]
      for (name, value) in _semanticAlignment(leading) { column.attributes[name] = value }
      column.attributes["data-layout-kind"] = "vstack"
      column.attributes["data-layout-schema"] = "1"
      column.attributes["data-layout-gap"] = _semanticNumber(20)
      column.children = [child]
      // On a wide screen the grouped content keeps a readable width and sits in the middle, as on iPad.
      let limit = _RenderNode.element("div")
      limit.classes = ["frame-box"]
      for (name, value) in _semanticFrame(["max-w": 720], leading) { limit.attributes[name] = value }
      limit.attributes["data-layout-schema"] = "1"
      limit.children = [column]
      let fill = _RenderNode.element("div")
      fill.classes = ["frame-box"]
      for (name, value) in _semanticFrame(["max-w": Double.infinity], Alignment(horizontal: .center, vertical: .top)) { fill.attributes[name] = value }
      fill.attributes["data-layout-schema"] = "1"
      fill.children = [limit]
      let inset = _RenderNode.element("div")
      inset.classes = ["padding-box"]
      inset.attributes["data-layout-kind"] = "padding"
      inset.attributes["data-layout-schema"] = "1"
      for edge in ["top", "leading", "bottom", "trailing"] { inset.attributes["data-padding-" + edge] = "16" }
      inset.children = [fill]
      return [inset]
    }
    return []
  }
}

public nonisolated struct List<Content: View>: View {
  public typealias Body = Never
  package let content: Content
  /// Set by the `selection:` initializers; rows (`NavigationLink(value:)`, tagged rows) read it from the environment.
  package var _selection: _ListSelection?
  public nonisolated init(@ViewBuilder content: () -> Content) { self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("ul")
    // SwiftUI List owns its vertical scrolling container.  Marking the
    // semantic root with the same internal scroll classes used by ScrollView
    // lets BrowserApp attach one coalesced range handler even when callers do
    // not wrap a List in an explicit ScrollView.
    node.classes = ["list-view", "scroll-view", "scroll-vertical"]
    _ScrollNode(id: _ScrollNode.id(for: context, kind: "list"), axes: .vertical).apply(to: node)
    // List keeps the normal SwiftUI syntax while opting its collection
    // descendants into the renderer's deferred range path. The flag is
    // inherited from FiberTree: static/WASI renderers leave it disabled and
    // therefore retain deterministic eager HTML. ForEach keeps the
    // small-collection threshold for List/Table; explicit Lazy* containers
    // set a force-deferred bit so their contract is honored for every size.
    var listContext = context
    if let _selection { listContext.environment[_ListSelectionKey.self] = _selection }
    if context.lazyCollectionsEnabled {
      listContext.lazyAxis = .vertical
      listContext.lazyLaneCount = 1
    }
    // The lazy mark is derived from the content, which a deep render hands to the loop that drives the pass.
    if _RenderStaging.wantsDeferral {
      _deferChild(content, context: listContext.child(_FiberKey("content")), to: node, completion: .lazyCollection)
      return node
    }
    let child = content._render(in: listContext.child(_FiberKey("content")))
    node.children = child.isEmpty ? [] : [child]
    if _RenderStaging.hasPending {
      _postponeCompletion(.lazyCollection, of: node, child: child)
    } else if _containsLazyCollection(in: child) {
      node.attributes["data-lazy"] = "vertical"
    }
    return node
  }
}

// SwiftUI-style data initializers keep the existing `List { ... }` spelling
// source-compatible while giving the renderer a keyed collection descriptor
// it can virtualize without evaluating every row body.
public extension List {
  nonisolated init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, RowContent> {
    self.init { ForEach(data, id: id, content: rowContent) }
  }

  nonisolated init<Data: RandomAccessCollection, RowContent: View>(
    _ data: Data,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
    self.init { ForEach(data, content: rowContent) }
  }
}

func _containsLazyCollection(in root: _RenderNode) -> Bool {
  var pending = [root]
  while let node = pending.popLast() {
    if node.lazyCollection != nil { return true }
    for child in node.children.reversed() { pending.append(child) }
  }
  return false
}

public struct Section<Header: View, Content: View, Footer: View> {
  public typealias Body = Never
  package let header: Header; package let content: Content; package let footer: Footer
  public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) { self.content = content(); self.header = header(); self.footer = footer() }
  @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Header == Text, Footer == EmptyView { header = Text(String(title)); self.content = content(); footer = EmptyView() }
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Header == Text, Footer == EmptyView { self.init(titleKey.resolved, content: content) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("section")
    node.classes = ["section-block"]
    let headerContent = header._render(in: context)
    // The rows and the footer are laid out from what the content renders, so a deep render builds them where the
    // content renders, in the same order (content, then footer).
    if _RenderStaging.wantsDeferral {
      let content = self.content, footer = self.footer
      _deferBuiltChildren(of: node) {
        let c = content._render(in: context.child(_FiberKey("content")))
        let f = footer._render(in: context.child(_FiberKey("footer")))
        return Self.sectionChildren(header: headerContent, content: c, footer: f)
      }
    } else {
      let c = content._render(in: context.child(_FiberKey("content")))
      let f = footer._render(in: context.child(_FiberKey("footer")))
      node.children = Self.sectionChildren(header: headerContent, content: c, footer: f)
    }
    // A section fills the width of its form or list and lays its rows out from the leading edge, as in SwiftUI;
    // left alone the browser layout shrinks it to its widest row and centres that.
    let leading = Alignment(horizontal: .leading, vertical: .center)
    for (name, value) in _semanticAlignment(leading) { node.attributes[name] = value }
    node.attributes["data-layout-kind"] = "vstack"
    node.attributes["data-layout-gap"] = _semanticNumber(0)
    _semanticWrap(node, kind: "frame")
    for (name, value) in _semanticFrame(["max-w": Double.infinity], leading) { node.attributes[name] = value }
    return node
  }

  /// The children of a section for what its header, content and footer rendered.
  @MainActor private static func sectionChildren(header headerContent: _RenderNode, content c: _RenderNode, footer f: _RenderNode) -> [_RenderNode] {
    var children: [_RenderNode] = []
    if !headerContent.isEmpty {
      let h = _RenderNode.element("div")
      h.classes = ["section-heading"]
      h.attributes["data-layout-kind"] = "padding"
      h.attributes["data-layout-schema"] = "1"
      h.attributes["data-padding-top"] = "4"; h.attributes["data-padding-bottom"] = "4"
      h.attributes["data-padding-leading"] = "16"; h.attributes["data-padding-trailing"] = "16"
      h.children = _semanticHeld(headerContent)
      children.append(h)
    }
    // Rows keep the vertical rhythm and side margin of a grouped list.
    // Fragments are flattened in document order by a loop: nested fragments can follow the depth of the content.
    var rowNodes: [_RenderNode] = []
    var pending = [c]
    while let node = pending.popLast() {
      if node.kind == .fragment { pending.append(contentsOf: node.children.reversed()) } else { rowNodes.append(node) }
    }
    var paddedRows: [_RenderNode] = []
    for row in rowNodes where !row.isEmpty {
      let padded = _RenderNode.element("div")
      padded.classes = ["padding-box"]
      padded.attributes["data-layout-kind"] = "padding"
      padded.attributes["data-layout-schema"] = "1"
      padded.attributes["data-padding-top"] = "12"; padded.attributes["data-padding-bottom"] = "12"
      padded.attributes["data-padding-leading"] = "16"; padded.attributes["data-padding-trailing"] = "16"
      padded.children = [row]
      // The row fills the card so its divider spans it, whatever the row's own width.
      let rowFill = _RenderNode.element("div")
      rowFill.classes = ["frame-box", "section-row"]
      for (name, value) in _semanticFrame(["max-w": Double.infinity, "min-h": 24], Alignment(horizontal: .leading, vertical: .center)) { rowFill.attributes[name] = value }
      rowFill.attributes["data-layout-schema"] = "1"
      rowFill.children = [padded]
      paddedRows.append(rowFill)
    }
    if !paddedRows.isEmpty {
      // The rows form one rounded group that fills the width; the header sits above it and the footer below.
      let rowsAlignment = Alignment(horizontal: .leading, vertical: .center)
      let column = _RenderNode.element("div")
      column.classes = ["vstack", "section-rows"]
      for (name, value) in _semanticAlignment(rowsAlignment) { column.attributes[name] = value }
      column.attributes["data-layout-kind"] = "vstack"
      column.attributes["data-layout-schema"] = "1"
      column.attributes["data-layout-gap"] = _semanticNumber(0)
      column.children = paddedRows
      let card = _RenderNode.element("div")
      card.classes = ["frame-box", "section-card"]
      for (name, value) in _semanticFrame(["max-w": Double.infinity], rowsAlignment) { card.attributes[name] = value }
      card.attributes["data-layout-schema"] = "1"
      card.children = [column]
      children.append(card)
    }
    if !f.isEmpty {
      let note = _RenderNode.element("div")
      note.classes = ["section-trailer", "padding-box"]
      note.attributes["data-layout-kind"] = "padding"
      note.attributes["data-layout-schema"] = "1"
      note.attributes["data-padding-top"] = "4"; note.attributes["data-padding-bottom"] = "10"
      note.attributes["data-padding-leading"] = "16"; note.attributes["data-padding-trailing"] = "16"
      note.children = _semanticHeld(f)
      children.append(note)
    }
    return children
  }
}
extension Section: View {}

public nonisolated struct ScrollView<Content: View>: View {
  public typealias Body = Never
  public nonisolated let axes: Axis.Set
  public let content: Content
  public nonisolated init(_ axes: Axis.Set = .vertical, @ViewBuilder content: () -> Content) { self.axes = axes; self.content = content() }
  /// The scroll bars are the browser's; the flag is accepted for source compatibility.
  public nonisolated init(_ axes: Axis.Set = .vertical, showsIndicators: Bool, @ViewBuilder content: () -> Content) { self.axes = axes; self.content = content() }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode { if context._endsLazyScope() { return _renderEndingLazyScope(self, in: context) }; let node = _RenderNode.element("div"); let directionClass = axes.contains(.horizontal) && axes.contains(.vertical) ? "scroll-both" : axes.contains(.horizontal) ? "scroll-horizontal" : "scroll-vertical"; node.classes = ["scroll-view", directionClass]; if context.environment.layoutDirection == .rightToLeft { node.attributes["dir"] = "rtl" }; _ScrollNode(id: _ScrollNode.id(for: context, kind: "scroll"), axes: axes).apply(to: node); let childContext = context.child(_FiberKey("content")); if _RenderStaging.wantsDeferral { _deferStackChild(content, context: childContext, to: node); return node }; let child = content._render(in: childContext); node.children = child.isEmpty ? [] : [child]; return node }
}

public nonisolated struct Picker<SelectionValue: Hashable, Content: View>: View {
  public typealias Body = Never
  package let title: String
  package let selection: Binding<SelectionValue>
  package let content: Content
  /// A view label (`Picker(selection:content:label:)`), drawn in place of the title text.
  private var labelView: AnyView?
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) { self.title = String(title); self.selection = selection; self.content = content() }
 public nonisolated init<Label: View>(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    title = ""
    self.selection = selection
    self.content = content()
    labelView = AnyView(label())
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) { self.init(titleKey.resolved, selection: selection, content: content) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("label")
    node.classes = ["picker-control"]
    node.attributes["data-control-kind"] = "picker"
    let labelsHidden = context.environment._labelsHidden
    // A menu picker with hidden labels is SwiftUI's building block for a
    // custom field: render only a chrome-less native select that fills the
    // picker's frame and inherits font and color.
    let plainChrome = labelsHidden && context.environment._pickerStyle == "menu"
    if plainChrome { node.attributes["data-field-chrome"] = "plain" }
    let titleNode = _RenderNode.element("span")
    titleNode.classes = ["picker-label"]
    if let labelView {
      titleNode.children = [labelView._render(in: context.child(_FiberKey("label")))]
    } else {
      titleNode.children = [.text(title)]
      // An empty title has no visible label or spacing, but keeps the control's
      // sibling identity stable if its title changes later.
      if title.isEmpty { titleNode.styles["display"] = "none" }
    }
    let select = _RenderNode.element("select")
    select.classes = ["select-menu"]
    if plainChrome { select.attributes["data-field-chrome"] = "plain" }
    _AccessibilityBackend.setLabel(title, on: select)
    // Native select options belong to the control, not the surrounding lazy
    // viewport. Deferring them would discard their tags during extraction.
    var optionsContext = context.child(_FiberKey("options"))
    optionsContext.lazyCollectionsEnabled = false
    optionsContext.lazyCollectionsForceDeferred = false
    optionsContext.lazyAxis = nil
    optionsContext.lazyLaneCount = nil
    // The options are rendered only to read their labels and tags: the nodes are dropped and no Fiber holds them, so
    // owners registered for them would stay registered for good (each pass registered a picker's options again). Their
    // reads land on the picker's owner, which renders them again when one changes.
    optionsContext._renderOwnerRegistry = nil
    // The picker reads its options once the pass has rendered them, the deferred ones included (see `_StagedRender`).
    _RenderStaging.enterStage()
    let renderedContent = content._render(in: optionsContext)
    _RenderStaging.exitStage()
    let segmented = context.environment._pickerStyle == "segmented"
    let isGrouped = !labelsHidden && !segmented && context.environment[_GroupedListKey.self]
    let result: _RenderNode = segmented ? _segmentedPickerNode(title: title, context: context) : node
    if isGrouped {
      // A picker row in a form reads label first and its menu at the trailing edge, filling its row, as in SwiftUI.
      node.classes.append("picker-row")
      node.classes.append("hstack")
      node.attributes["data-layout-kind"] = "hstack"
      node.attributes["data-layout-schema"] = "1"
      node.attributes["data-layout-gap"] = _semanticNumber(0)
      node.attributes["data-align-x"] = "0.5"
      node.attributes["data-align-y"] = "0.5"
    }
    let selection = self.selection
    return _RenderStaging.stagedNode { stage in
      stage.whenSettled { stage in
        let candidates = _pickerOptionCandidates(in: renderedContent)
        var valuesByToken: [String: _RuntimeValue] = [:]
        // One token per candidate (nil when it does not read as the selection type). Two options whose tokens would
        // coincide (different tags with one description) get a numbered suffix, so each option keeps its own value.
        var tokens: [String?] = []
        var optionNodes: [_RenderNode] = []
        for candidate in candidates {
          guard let value = candidate.value.read(SelectionValue.self) else { tokens.append(nil); continue }
          let described = _selectionDescription(value)
          let base = candidate.explicitToken ?? (described.isEmpty ? candidate.tagToken : described)
          var token = base
          var suffix = 1
          while valuesByToken[token] != nil {
            token = base + "#" + String(suffix)
            suffix += 1
          }
          tokens.append(token)
          valuesByToken[token] = candidate.value
          let option = _RenderNode.element("option")
          option.classes = ["option-item"]
          option.attributes["value"] = token
          if value == selection.wrappedValue { option.attributes["selected"] = "selected" }
          option.children = [.text(candidate.label)]
          optionNodes.append(option)
        }
        select.children = optionNodes
        let optionTokens = tokens
        if segmented {
          let isEnabled = context.environment.isEnabled
          let segments = candidates.compactMap { candidate -> _SegmentedPickerOption? in
            guard let value = candidate.value.read(SelectionValue.self) else { return nil }
            return _SegmentedPickerOption(
              label: candidate.label,
              content: candidate.node,
              isSelected: { selection.wrappedValue == value },
              select: { if isEnabled, selection.wrappedValue != value { selection.wrappedValue = value } }
            )
          }
          result.children = _segmentedPickerChildren(options: segments, sourceID: selection._sourceID, context: context)
          stage.complete(result)
          return
        }
        if let sourceID = selection._sourceID {
          select.leafBindings.append(_LeafBindingDescriptor(
            sourceID: sourceID,
            operation: .property("value"),
            value: {
              guard let index = candidates.firstIndex(where: { $0.value.read(SelectionValue.self) == selection.wrappedValue }) else {
                return ""
              }
              return optionTokens[index] ?? ""
            }
          ))
        }
        if context.environment.isEnabled {
          select.events["change"] = _EventHandler(name: "change", action: { rawValue in
            guard let value = valuesByToken[rawValue]?.read(SelectionValue.self) else { return }
            selection.wrappedValue = value
          })
        } else {
          select.attributes["disabled"] = "disabled"
          select.attributes["aria-disabled"] = "true"
        }
        if isGrouped {
          let spacer = _RenderNode.element("div")
          spacer.classes = ["flex-spacer"]
          spacer.attributes["data-layout-kind"] = "spacer"
          spacer.attributes["data-layout-schema"] = "1"
          spacer.attributes["data-spacer-min"] = "12"
          result.children = [titleNode, spacer, select]
          stage.complete(result)
          return
        }
        result.children = labelsHidden ? [select] : [titleNode, select]
        stage.complete(result)
      }
    }
  }
}

/// Native HTML color input with the SwiftUI `ColorPicker` spelling. CSS color
/// names remain valid public `Color` values; the browser input uses a stable
/// hexadecimal representation and writes the selected CSS color back through
/// the binding.
public nonisolated struct ColorPicker<Label: View>: View {
  public typealias Body = Never
  package let selection: Binding<Color>
  package let supportsOpacity: Bool
  package let label: Label

  public nonisolated init(
    selection: Binding<Color>,
    supportsOpacity: Bool = true,
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.supportsOpacity = supportsOpacity
    self.label = label()
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Color>,
    supportsOpacity: Bool = true
  ) where Label == Text {
    self.init(selection: selection, supportsOpacity: supportsOpacity) { Text(LocalizedStringKey(String(title)).resolved) }
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<Color>, supportsOpacity: Bool = true) where Label == Text { self.init(titleKey.resolved, selection: selection, supportsOpacity: supportsOpacity) }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("label")
    node.classes = ["color-picker"]
    node.attributes["data-control-kind"] = "color-picker"
    let labelNode = label._render(in: context.child(_FiberKey("label")))
    let input = _RenderNode.element("input")
    input.classes = ["color-input"]
    input.attributes["type"] = "color"
    input.attributes["value"] = _colorInputValue(selection.wrappedValue)
    input.attributes["data-supports-opacity"] = supportsOpacity ? "true" : "false"
    if let sourceID = selection._sourceID {
      input.leafBindings.append(_LeafBindingDescriptor(
        sourceID: sourceID,
        operation: .property("value"),
        value: { _colorInputValue(selection.wrappedValue) }
      ))
    }
    if context.environment.isEnabled {
      input.events["input"] = _EventHandler(name: "input", action: { selection.wrappedValue = Color($0) })
      input.events["change"] = _EventHandler(name: "change", action: { selection.wrappedValue = Color($0) })
    } else {
      input.attributes["disabled"] = "disabled"
      input.attributes["aria-disabled"] = "true"
    }
    if let text = _toggleAccessibilityText(labelNode), !text.isEmpty { _AccessibilityBackend.setLabel(text, on: input) }
    let visibleLabel = context.environment._labelsHidden ? _RenderNode.fragment() : labelNode
    if !context.environment._labelsHidden, !labelNode.isEmpty, context.environment[_GroupedListKey.self] {
      // In a form the colour well sits at the trailing edge of its row.
      let spacer = _RenderNode.element("div")
      spacer.classes = ["flex-spacer"]
      spacer.attributes["data-layout-kind"] = "spacer"
      spacer.attributes["data-layout-schema"] = "1"
      spacer.attributes["data-spacer-min"] = "12"
      node.classes.append("hstack")
      node.attributes["data-layout-kind"] = "hstack"
      node.attributes["data-layout-schema"] = "1"
      node.attributes["data-layout-gap"] = _semanticNumber(0)
      node.attributes["data-align-x"] = "0.5"
      node.attributes["data-align-y"] = "0.5"
      input.attributes["data-layout-kind"] = "size"
      input.attributes["data-layout-schema"] = "1"
      input.attributes["data-size-w"] = "32"
      input.attributes["data-size-h"] = "32"
      node.children = [labelNode, spacer, input]
      return node
    }
    node.children = [visibleLabel, input].filter { !$0.isEmpty }
    return node
  }
}

package nonisolated struct Option<Label: View>: View {
  public typealias Body = Never
  package let value: String; package let label: Label
  package init(value: String, @ViewBuilder label: () -> Label) { self.value = value; self.label = label() }
  @_disfavoredOverload package init(_ title: String, value: String) where Label == Text { self.init(value: value) { Text(title) } }
  package init(_ titleKey: LocalizedStringKey, value: String) where Label == Text { self.init(titleKey.resolved, value: value) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("option")
    node.classes = ["option-item"]
    node.attributes["value"] = value
    node._pickerSelectionValue = _RuntimeValue(value)
    let child = label._render(in: context)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public nonisolated struct Label<Title: View, Icon: View>: View {
  public typealias Body = Never
  package let title: Title; package let icon: Icon
  public nonisolated init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) { self.title = title(); self.icon = icon() }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, systemImage: String) where Title == Text, Icon == Image { self.title = Text(String(title)); self.icon = Image(systemName: systemImage) }
  public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String) where Title == Text, Icon == Image { self.init(titleKey.resolved, systemImage: systemImage) }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, image: String) where Title == Text, Icon == Image { self.title = Text(String(title)); self.icon = Image(image) }
  public nonisolated init(_ titleKey: LocalizedStringKey, image: String) where Title == Text, Icon == Image { self.init(titleKey.resolved, image: image) }
  /// Rendering honors the inherited `labelStyle(_:)` (see LabelStyle.swift).
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode { _renderLabel(title: title, icon: icon, in: context) }
}

/// A reusable empty/error/search state surface matching SwiftUI's
/// `ContentUnavailableView` shape.  Actions and descriptions remain ordinary
/// Views, so applications can provide their own copy and controls.
public nonisolated struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
  public typealias Body = Never
  package let label: Label
  package let description: Description
  package let actions: Actions

  public nonisolated init(
    @ViewBuilder label: () -> Label,
    @ViewBuilder description: () -> Description = { EmptyView() },
    @ViewBuilder actions: () -> Actions = { EmptyView() }
  ) {
    self.label = label(); self.description = description(); self.actions = actions()
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, systemImage: String) where Label == Text, Description == EmptyView, Actions == EmptyView {
    self.label = Text(LocalizedStringKey(String(title)).resolved)
    self.description = EmptyView()
    self.actions = EmptyView()
    self._systemImage = systemImage
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String) where Label == Text, Description == EmptyView, Actions == EmptyView { self.init(titleKey.resolved, systemImage: systemImage) }

  /// SwiftUI's `ContentUnavailableView(_:systemImage:description:)`.
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, systemImage: String, description: Text?) where Label == Text, Description == Text, Actions == EmptyView {
    self.label = Text(LocalizedStringKey(String(title)).resolved)
    self.description = description ?? Text("")
    self.actions = EmptyView()
    self._systemImage = systemImage
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text?) where Label == Text, Description == Text, Actions == EmptyView { self.init(titleKey.resolved, systemImage: systemImage, description: description) }

  /// Symbol shown above the title by the title/systemImage initializers.
  private var _systemImage: String? = nil

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["content-unavailable"]
    let labelNode = label._render(in: context.child(_FiberKey("label")))
    let descriptionNode = description._render(in: context.child(_FiberKey("description")))
    let actionsNode = actions._render(in: context.child(_FiberKey("actions")))
    let iconNode = _systemImage.map { Image(systemName: $0)._render(in: context.child(_FiberKey("icon"))) } ?? .empty()
    if !iconNode.isEmpty {
      iconNode.classes.append("content-unavailable-icon")
      iconNode.attributes["aria-hidden"] = "true"
    }
    node.children = [iconNode, labelNode, descriptionNode, actionsNode].filter { !$0.isEmpty && !($0.kind == .text && ($0.text ?? "").isEmpty) }
    return node
  }
}

/// The parts of `ContentUnavailableView.search`, named as in SwiftUI's `SearchUnavailableContent`. The copy is a
/// localized key, so an application's string catalog translates it as it does its own strings.
public struct SearchUnavailableContent {
  /// The title of the search state.
  public nonisolated struct Label: View {
    public typealias Body = Never
    package let text: Text
    @MainActor public func _render(in context: _RenderContext) -> _RenderNode { text._render(in: context) }
  }
  /// The explanation under the title of the search state.
  public nonisolated struct Description: View {
    public typealias Body = Never
    package let text: Text
    @MainActor public func _render(in context: _RenderContext) -> _RenderNode { text._render(in: context) }
  }
  /// The actions of the search state; the stock search state has none.
  public nonisolated struct Actions: View {
    public typealias Body = Never
    @MainActor public func _render(in context: _RenderContext) -> _RenderNode { EmptyView()._render(in: context) }
  }
}

/// SwiftUI's `ContentUnavailableView.search` and `ContentUnavailableView.search(text:)`: the "No Results" state of a search.
public extension ContentUnavailableView where Label == SearchUnavailableContent.Label, Description == SearchUnavailableContent.Description, Actions == SearchUnavailableContent.Actions {
  static var search: ContentUnavailableView<SearchUnavailableContent.Label, SearchUnavailableContent.Description, SearchUnavailableContent.Actions> {
    _searchContent(title: Text("No Results"))
  }

  static func search(text: String) -> ContentUnavailableView<SearchUnavailableContent.Label, SearchUnavailableContent.Description, SearchUnavailableContent.Actions> {
    _searchContent(title: Text("No Results for “\(text)”"))
  }

  /// The magnifying glass is the stock search state's symbol, set on the view the same way `init(_:systemImage:)` does.
  private static func _searchContent(title: Text) -> ContentUnavailableView<SearchUnavailableContent.Label, SearchUnavailableContent.Description, SearchUnavailableContent.Actions> {
    var view = ContentUnavailableView<SearchUnavailableContent.Label, SearchUnavailableContent.Description, SearchUnavailableContent.Actions>(
      label: { SearchUnavailableContent.Label(text: title) },
      description: { SearchUnavailableContent.Description(text: Text("Check the spelling or try a new search.")) },
      actions: { SearchUnavailableContent.Actions() }
    )
    view._systemImage = "magnifyingglass"
    return view
  }
}

/// A column of a `Table`: its header and the cell built from each row value.
/// Apple's `TableColumnContent`; `_renderTableColumns` is SwiftUIWeb's renderer
/// hook and is outside the SwiftUI surface.
@MainActor @preconcurrency
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
  associatedtype TableRowValue: Identifiable
  associatedtype TableColumnSortComparator
  associatedtype TableColumnBody

  func _renderTableColumns(in context: _RenderContext) -> _RenderNode
}

/// One table column. The browser renders the header as a `th` that keeps the typed cell
/// closure as renderer-only metadata, so a deferred table can render only visible rows.
public nonisolated struct TableColumn<RowValue, Sort, Content, Label>: TableColumnContent
where RowValue: Identifiable, Content: View, Label: View {
  public typealias TableRowValue = RowValue
  public typealias TableColumnSortComparator = Sort
  public typealias TableColumnBody = Never
  let title: String
  let cell: (RowValue) -> Content
  /// Sorting and sizing metadata installed by the initializers in
  /// `TableSorting.swift` and the `width` modifiers.
  package var _sort: _TableColumnSort<Sort>?
  var _widthStyles: _NodeValues = [:]

  package init(title: String, cell: @escaping (RowValue) -> Content) {
    self.title = title
    self.cell = cell
  }

  @MainActor public func _renderTableColumns(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("th")
    node.classes = ["table-view-column"]
    node.attributes["scope"] = "col"
    node.attributes["data-table-column"] = title
    node.children = [.text(title)]
    if let _sort { node._tableColumnSort = _RuntimeValue(_sort) }
    for (key, value) in _widthStyles { node.styles[key] = value }
    // Keep the typed cell closure attached to the semantic header node.  A
    // deferred Table descriptor can then render only visible rows without
    // reflecting over `Columns` or evaluating every row up front.
    node._tableCellRender = { row, cellContext in
      guard let value: RowValue = row.read() else { return .empty() }
      return AnyView(self.cell(value))._render(in: cellContext)
    }
    return node
  }
}

/// A table of rows drawn from `Rows` and columns drawn from `Columns`.
public nonisolated struct Table<Value, Rows, Columns>: View
where Value == Rows.TableRowValue, Rows: TableRowContent, Columns: TableColumnContent,
  Rows.TableRowValue == Columns.TableRowValue {
  public typealias Body = Never
  let rows: Rows
  let columns: Columns
  /// Selection and sort-order wiring installed by the initializers in
  /// `TableSorting.swift`.
  package var _selection: _ListSelectionSink<Value.ID>?
  package var _sortWiring: (@MainActor (_RenderNode) -> Void)?

  package init(rows: Rows, columns: Columns) {
    self.rows = rows
    self.columns = columns
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let table = _RenderNode.element("table")
    table.classes = ["table-view"]
    let head = _RenderNode.element("thead")
    let row = _RenderNode.element("tr")
    let headers = columns._renderTableColumns(in: context.child(_FiberKey("columns")))
    if headers.kind == .fragment { row.children = headers.children } else if !headers.isEmpty { row.children = [headers] }
    _sortWiring?(row)
    head.children = [row]
    var rowContext = context.child(_FiberKey("rows"))
    rowContext.lazyAxis = nil
    var collected: [Value] = []
    _collectTableRows(rows._renderTableRows(in: rowContext), into: &collected)
    let values = collected
    let selection = _selection
    if selection != nil { table.attributes["aria-multiselectable"] = "true" }
    let body = _RenderNode.element("tbody")
    body.classes = ["table-body"]

    // TableColumn nodes retain an erased renderer closure in renderer-only
    // metadata.  This lets both eager and deferred paths render real cells
    // while the public `Table`/`TableColumn` API remains unchanged.
    let columnRenderers = _tableCellRenderers(in: headers)
    // A row with an id already used by an earlier row gets its own occurrence key, as a ForEach row does.
    let rowKeys = _occurrenceKeys(values.map { _FiberKey($0.id) })
    let makeRow: (Int, _RenderContext) -> _RenderNode = { offset, rowContext in
      let item = values[offset]
      let tr = _RenderNode.element("tr")
      let rowKey = rowKeys[offset]
      tr.key = rowKey
      tr.attributes["data-row-id"] = fiberKeyDescription(rowKey)
      if let selection {
        let id = item.id
        let selected = selection.isSelected(id)
        tr.attributes["aria-selected"] = selected ? "true" : "false"
        tr.attributes["tabindex"] = "0"
        if selected { tr.attributes["data-selected"] = "true" }
        tr.events["click"] = _EventHandler(name: "click", action: { selection.select(id) })
      }
      if columnRenderers.isEmpty {
        let cell = _RenderNode.element("td")
        cell.key = _FiberKey("__table_column_0")
        cell.children = [.text(_swiftUIWebDescribe(item))]
        tr.children = [cell]
      } else {
        tr.children = columnRenderers.enumerated().map { index, renderer in
          let cell = _RenderNode.element("td")
          let key = _FiberKey("__table_column_\(index)")
          cell.key = key
          let rendered = renderer(_RuntimeValue(item), rowContext.child(key))
          cell.children = rendered.isEmpty ? [] : [rendered]
          return cell
        }
      }
      return tr
    }

    if context.lazyCollectionsEnabled, values.count > _lazyCollectionThreshold {
      #if hasFeature(Embedded)
      let itemType = ""
      #else
      let itemType = _swiftUIWebTypeName(Value.self)
      #endif
      let rowKeySet = Set(rowKeys)
      let descriptor = _LazyCollectionDescriptor(
        count: values.count,
        axis: .vertical,
        estimatedExtent: 40,
        laneCount: 1,
        itemType: itemType,
        spacerTag: "tr",
        spacerColumnCount: max(1, columnRenderers.count),
        keyAt: { offset in
          return rowKeys[offset]
        },
        containsKey: { rowKeySet.contains($0) },
        renderItem: { offset, rowContext in
          // Include the application row identity in every cell's state path;
          // physical recycling must never make two rows share SwiftUI state.
          return makeRow(offset, rowContext.child(rowKeys[offset]))
        }
      )
      body.lazyCollection = descriptor
      body.attributes["data-lazy"] = "vertical"
    } else {
      body.children = values.indices.map { makeRow($0, context.child(rowKeys[$0])) }
    }
    table.children = [head, body]
    return table
  }
}

/// Recursively extracts renderer metadata emitted by `TableColumn` nodes.
/// Columns are commonly wrapped in `Group`/tuple view fragments, so walking
/// the semantic header tree avoids relying on a particular result-builder
/// shape and keeps this helper entirely inside Core.
private func _tableCellRenderers(in root: _RenderNode) -> [((_RuntimeValue, _RenderContext) -> _RenderNode)] {
  // A loop in document order: the header tree can nest as deep as the view that built it.
  var result: [((_RuntimeValue, _RenderContext) -> _RenderNode)] = []
  var stack = [root]
  while let node = stack.popLast() {
    if let renderer = node._tableCellRender { result.append(renderer) }
    stack.append(contentsOf: node.children.reversed())
  }
  return result
}

/// A disclosure-backed menu that preserves native keyboard and pointer
/// behavior while allowing ordinary SwiftUI `Button` actions in its content.
/// The browser can style the menu without requiring a JavaScript-specific API.
public nonisolated struct Menu<Label: View, Content: View>: View {
  public typealias Body = Never
  package let label: Label
  package let content: Content

  public nonisolated init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.content = content()
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(content: content) { Text(LocalizedStringKey(String(title)).resolved) }
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, content: content) }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("details")
    node.classes = ["menu-popup"]
    // A menu under a plain, borderless or custom button style is just its label, as in SwiftUI: no chrome, no caret.
    let style = context.environment.buttonStyle
    if context.environment.buttonStyleIsCustom || style == .plain || style == .borderless || style == .link {
      node.classes.append("menu-plain")
    }
    node.attributes["data-control-kind"] = "menu"
    let summary = _RenderNode.element("summary")
    summary.attributes["role"] = "button"
    summary.attributes["aria-haspopup"] = "menu"
    summary.attributes["aria-expanded"] = "false"
    summary.children = [label._render(in: context.child(_FiberKey("label")))]
    let menu = _RenderNode.element("div")
    menu.attributes["role"] = "menu"
    // A manual popover: the host shows it in the browser's top layer (above every stacking context, never clipped by an
    // ancestor's overflow) while the `<details>` is open, and places it under the summary.
    menu.attributes["popover"] = "manual"
    let contentContext = context.child(_FiberKey("content"))
    if _RenderStaging.wantsDeferral {
      _deferStackChild(content, context: contentContext, to: menu)
    } else {
      let renderedContent = content._render(in: contentContext)
      menu.children = renderedContent.isEmpty ? [] : [renderedContent]
    }
    node.children = [summary, menu]
    return node
  }
}

public struct GridItem: Hashable, Sendable {
  public enum Size: Hashable, Sendable {
    case adaptive(minimum: Double, maximum: Double = .infinity)
    case fixed(Double)
    case flexible(minimum: Double = 10, maximum: Double = .infinity)

  }
  public let size: Size; public let spacing: Double?; public let alignment: Alignment?
  public init(_ size: GridItem.Size = .flexible(), spacing: Double? = nil, alignment: Alignment? = nil) { self.size = size; self.spacing = spacing; self.alignment = alignment }
}

public nonisolated struct LazyVGrid<Content: View>: View {
  public typealias Body = Never
  package let columns: [GridItem]
  package let alignment: HorizontalAlignment
  package let spacing: Double?
  package let content: Content
  public nonisolated init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {
    self.columns = columns; self.alignment = alignment; self.spacing = spacing; self.content = content()
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["grid-layout"]
    node.attributes["data-lazy"] = "vertical"
    node.styles["align-items"] = alignment.cssValue
    node.styles["grid-template-columns"] = columns.map(_gridTrack).joined(separator: " ")
    node.attributes["data-layout-kind"] = "grid"
    node.attributes["data-grid-tracks"] = columns.map(_semanticGridTrack).joined(separator: "|")
    // `spacing` separates rows; columns are separated by `GridItem.spacing`.
    node.attributes["data-layout-gap"] = String(_defaultGridSpacing)
    node.attributes["data-row-spacing"] = String(spacing ?? _defaultGridSpacing)
    for (name, value) in _semanticAlignment(Alignment(horizontal: alignment, vertical: .center)) { node.attributes[name] = value }
    if let spacing { node.styles["gap"] = "\(spacing.clean)px" }
    var lazyContext = context
    lazyContext.lazyAxis = .vertical
    lazyContext.lazyCollectionsForceDeferred = true
    lazyContext.lazyLaneCount = max(1, columns.count)
    if _RenderStaging.wantsDeferral { _deferStackChild(content, context: lazyContext, to: node); return node }
    let child = content._render(in: lazyContext)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public nonisolated struct LazyHGrid<Content: View>: View {
  public typealias Body = Never
  package let rows: [GridItem]
  package let alignment: VerticalAlignment
  package let spacing: Double?
  package let content: Content
  public nonisolated init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> Content) {
    self.rows = rows; self.alignment = alignment; self.spacing = spacing; self.content = content()
  }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["grid-layout", "hgrid"]
    node.attributes["data-lazy"] = "horizontal"
    node.styles["align-items"] = alignment.cssValue
    node.styles["grid-template-rows"] = rows.map(_gridTrack).joined(separator: " ")
    node.attributes["data-layout-kind"] = "grid"
    node.attributes["data-grid-tracks"] = rows.map(_semanticGridTrack).joined(separator: "|")
    // `spacing` separates columns; rows are separated by `GridItem.spacing`.
    node.attributes["data-layout-gap"] = String(_defaultGridSpacing)
    node.attributes["data-row-spacing"] = String(spacing ?? _defaultGridSpacing)
    for (name, value) in _semanticAlignment(Alignment(horizontal: .center, vertical: alignment)) { node.attributes[name] = value }
    if let spacing { node.styles["gap"] = "\(spacing.clean)px" }
    var lazyContext = context
    lazyContext.lazyAxis = .horizontal
    lazyContext.lazyCollectionsForceDeferred = true
    lazyContext.lazyLaneCount = max(1, rows.count)
    if _RenderStaging.wantsDeferral { _deferStackChild(content, context: lazyContext, to: node); return node }
    let child = content._render(in: lazyContext)
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

/// A regular SwiftUI grid.  Unlike `LazyVGrid`, a regular grid keeps its
/// children in explicit rows (`GridRow`) and therefore has no virtualization
/// policy.  Semantic layout sizes its columns from the widest cell of each
/// column and places every cell with the grid's (or its row's) alignment; a
/// child that is not a `GridRow` spans all columns.
public nonisolated struct Grid<Content: View>: View {
  public typealias Body = Never
  package let alignment: Alignment
  package let horizontalSpacing: Double?
  package let verticalSpacing: Double?
  package let content: Content

  public nonisolated init(
    alignment: Alignment = .center,
    horizontalSpacing: Double? = nil,
    verticalSpacing: Double? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.horizontalSpacing = horizontalSpacing
    self.verticalSpacing = verticalSpacing
    self.content = content()
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["grid-layout", "regular-grid"]
    node.styles["justify-items"] = alignment.horizontalValue
    node.styles["align-items"] = alignment.verticalValue
    if let horizontalSpacing { node.styles["column-gap"] = "\(horizontalSpacing.clean)px" }
    if let verticalSpacing { node.styles["row-gap"] = "\(verticalSpacing.clean)px" }
    node.attributes["data-layout-kind"] = "table"
    node.attributes["data-layout-gap"] = String(horizontalSpacing ?? _defaultGridSpacing)
    node.attributes["data-row-spacing"] = String(verticalSpacing ?? _defaultGridSpacing)
    for (name, value) in _semanticAlignment(alignment) { node.attributes[name] = value }
    if _RenderStaging.wantsDeferral { _deferStackChild(content, context: context.child(_FiberKey("content")), to: node); return node }
    let child = content._render(in: context.child(_FiberKey("content")))
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

public nonisolated struct GridRow<Content: View>: View {
  public typealias Body = Never
  package let alignment: VerticalAlignment?
  package let content: Content
  public nonisolated init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {
    self.alignment = alignment
    self.content = content()
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["grid-row"]
    node.attributes["data-layout-kind"] = "gridrow"
    if let alignment {
      node.styles["align-items"] = alignment.cssValue
      node.attributes["data-row-align-y"] = _semanticAlignment(Alignment(horizontal: .center, vertical: alignment))["data-align-y"]
    }
    if _RenderStaging.wantsDeferral { _deferStackChild(content, context: context.child(_FiberKey("content")), to: node); return node }
    let child = content._render(in: context.child(_FiberKey("content")))
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

private func _gridTrack(_ item: GridItem) -> String {
  switch item.size {
  case .adaptive(let minimum, let maximum): return "repeat(auto-fit, minmax(\(minimum.clean)px, \(maximum.isFinite ? maximum.clean + "px" : "1fr")))"
  case .fixed(let value): return "\(value.clean)px"
  case .flexible(let minimum, let maximum): return "minmax(\(minimum.clean)px, \(maximum.isFinite ? maximum.clean + "px" : "1fr"))"
  }
}

public nonisolated struct DisclosureGroup<Label: View, Content: View>: View {
  public typealias Body = Never
  package let label: Label
  package let content: Content
  package let isExpanded: Binding<Bool>?
  public nonisolated init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) { self.content = content(); self.label = label(); isExpanded = nil }
  /// SwiftUI-compatible binding initializer used by controls such as
  /// `OutlineGroup`.  Keeping the binding on the semantic disclosure node
  /// means browser clicks update Swift state while the native `<details>`
  /// element still supplies keyboard/touch disclosure behavior.
  public nonisolated init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.content = content(); self.label = label(); self.isExpanded = isExpanded
  }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text { self.label = Text(String(title)); self.content = content(); self.isExpanded = nil }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) where Label == Text { self.label = Text(String(title)); self.content = content(); self.isExpanded = isExpanded }
  public nonisolated init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, content: content) }
  public nonisolated init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, isExpanded: isExpanded, content: content) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("details")
    node.classes = ["disclosure-group"]
    if isExpanded?.wrappedValue == true { node.attributes["open"] = "open" }
    if isExpanded != nil { node.attributes["data-controlled-open"] = "true" }
    let summary = _RenderNode.element("summary")
    summary.classes = ["disclosure-summary"]
    if let isExpanded {
      _AccessibilityBackend.setState("expanded", isExpanded.wrappedValue ? "true" : "false", on: summary)
      if context.environment.isEnabled {
        summary.events["click"] = _EventHandler(name: "click", action: { isExpanded.wrappedValue.toggle() }, preventsDefault: true)
      } else {
        summary.attributes["aria-disabled"] = "true"
      }
    }
    let labelNode = label._render(in: context.child(_FiberKey("label")))
    let chevron = _RenderNode.element("span")
    chevron.classes = ["disclosure-chevron"]
    chevron.attributes["aria-hidden"] = "true"
    chevron.styles["width"] = "7px"
    chevron.styles["height"] = "7px"
    chevron.styles["flex-shrink"] = "0"
    chevron.styles["transform"] = isExpanded?.wrappedValue == true ? "rotate(225deg)" : "rotate(45deg)"
    summary.children = [labelNode, chevron]
    let contentNode = _RenderNode.element("div")
    contentNode.classes = ["disclosure-content"]
    let contentContext = context.child(_FiberKey("content"))
    if _RenderStaging.wantsDeferral {
      _deferStackChild(content, context: contentContext, to: contentNode)
    } else {
      let renderedContent = content._render(in: contentContext)
      contentNode.children = renderedContent.isEmpty ? [] : [renderedContent]
    }
    node.children = [summary, contentNode]
    return node
  }
}

public nonisolated struct ProgressView: View {
  public typealias Body = Never
  package let value: Double?
  package let total: Double
  package let title: String?
  public nonisolated init() { value = nil; total = 1; title = nil }
  public nonisolated init<V: BinaryFloatingPoint>(value: V?, total: V = 1) { self.value = value.map { Double($0) }; self.total = Double(total); title = nil }
  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S) { value = nil; total = 1; self.title = String(title) }
  public nonisolated init(_ titleKey: LocalizedStringKey) { self.init(titleKey.resolved) }
  @_disfavoredOverload public nonisolated init<S: StringProtocol, V: BinaryFloatingPoint>(_ title: S, value: V?, total: V = 1) { self.value = value.map { Double($0) }; self.total = Double(total); self.title = String(title) }
  public nonisolated init<V: BinaryFloatingPoint>(_ titleKey: LocalizedStringKey, value: V?, total: V = 1) { self.init(titleKey.resolved, value: value, total: total) }
  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // SwiftUI's automatic style is a spinner while indeterminate and a bar once it has a value; `.circular` draws a
    // ring for a value, `.linear` always draws the bar.
    let style = context.environment._progressViewStyle
    if style == "circular" || (style == "automatic" && value == nil) {
      let ring = _RenderNode.element("span")
      ring.attributes["data-control-kind"] = "progress-view"
      ring.attributes["role"] = "progressbar"
      // A fixed-size leaf (the stylesheet's 1.25rem): measured as an empty span it would report its two borders alone.
      ring.attributes["data-layout-kind"] = "size"
      ring.attributes["data-size-w"] = "20"
      ring.attributes["data-size-h"] = "20"
      if let title { _AccessibilityBackend.setLabel(title, on: ring) }
      if let value {
        ring.classes = ["progress-ring"]
        let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
        ring.styles["--progress-value"] = "\((fraction * 100).clean)%"
        _AccessibilityBackend.setNumeric("0", name: "valuemin", on: ring)
        _AccessibilityBackend.setNumeric("\(total.clean)", name: "valuemax", on: ring)
        _AccessibilityBackend.setNumeric("\(min(max(value, 0), total).clean)", name: "valuenow", on: ring)
      } else {
        ring.classes = ["spinner-ring"]
        ring.attributes["aria-busy"] = "true"
      }
      return ring
    }
    let node = _RenderNode.element("progress")
    node.classes = ["progress-bar"]
    node.attributes["data-control-kind"] = "progress-view"
    if let title { _AccessibilityBackend.setLabel(title, on: node) }
    node.attributes["max"] = "\(total.clean)"
    // Native progress controls can collapse to zero height when utility CSS
    // is unavailable. Keep the semantic track geometry explicit.
    node.styles["display"] = "block"
    node.styles["height"] = "8px"
    node.styles["min-height"] = "8px"
    node.styles["width"] = "100%"
    if let value {
      node.attributes["value"] = "\(value.clean)"
      _AccessibilityBackend.setNumeric("0", name: "valuemin", on: node)
      _AccessibilityBackend.setNumeric("\(total.clean)", name: "valuemax", on: node)
      _AccessibilityBackend.setNumeric("\(min(max(value, 0), total).clean)", name: "valuenow", on: node)
    }
    return node
  }
}

/// Semantic label/value pairing used by settings and inspector-style UIs.
/// The term/definition roles make the same view useful to screen readers and
/// leave visual layout to the host stylesheet.
public struct LabeledContent<Label: View, Content: View> {
  public typealias Body = Never
  package let label: Label
  package let content: Content

  public nonisolated init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.content = content()
  }

  @_disfavoredOverload public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(content: content, label: { Text(LocalizedStringKey(String(title)).resolved) })
  }
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, content: content) }

  @_disfavoredOverload public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) where Label == Text, Content == Text {
    self.init(content: { Text(String(value)) }, label: { Text(LocalizedStringKey(String(title)).resolved) })
  }
  public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) where Label == Text, Content == Text { self.init(titleKey.resolved, value: value) }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // The layout places the row: the label takes what the value leaves, with the row's 16pt spacing and 8pt of vertical
    // padding. Each cell is a stack, so nested content is described cell by cell instead of measured as one subtree.
    let node = _RenderNode.element("div")
    node.classes = ["labeled-content"]
    node.attributes["data-layout-kind"] = "labeledrow"
    node.attributes["data-layout-gap"] = "16"
    node.attributes["data-padding-top"] = "8"
    node.attributes["data-padding-bottom"] = "8"
    let labelNode = _RenderNode.element("span")
    labelNode.attributes["role"] = "term"
    labelNode.attributes["data-layout-kind"] = "zstack"
    labelNode.attributes["data-cell-kind"] = "labeled"
    let renderedLabel = label._render(in: context.child(_FiberKey("label")))
    labelNode.children = renderedLabel.isEmpty ? [] : [renderedLabel]
    let valueNode = _RenderNode.element("span")
    valueNode.attributes["role"] = "definition"
    valueNode.attributes["data-layout-kind"] = "zstack"
    valueNode.attributes["data-cell-kind"] = "labeled"
    let valueContext = context.child(_FiberKey("content"))
    if _RenderStaging.wantsDeferral {
      _deferStackChild(content, context: valueContext, to: valueNode)
    } else {
      let renderedValue = content._render(in: valueContext)
      valueNode.children = renderedValue.isEmpty ? [] : [renderedValue]
    }
    node.children = [labelNode, valueNode]
    return node
  }
}
extension LabeledContent: View {}

/// A fieldset-like container that preserves SwiftUI's `GroupBox` API while
/// producing semantic HTML.
public nonisolated struct GroupBox<Label: View, Content: View>: View {
  public typealias Body = Never
  package let label: Label
  package let content: Content

  public nonisolated init(label: Label, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  public nonisolated init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.label = label()
    self.content = content()
  }

  public nonisolated init(@ViewBuilder content: () -> Content) where Label == EmptyView {
    self.init(label: EmptyView(), content: content)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text {
    self.init(label: Text(LocalizedStringKey(String(title)).resolved), content: content)
  }
  public nonisolated init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text { self.init(titleKey.resolved, content: content) }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("fieldset")
    node.classes = ["group-box"]
    let legend = _RenderNode.element("legend")
    let renderedLabel = label._render(in: context.child(_FiberKey("label")))
    legend.children = renderedLabel.isEmpty ? [] : [renderedLabel]
    let contentContext = context.child(_FiberKey("content"))
    if _RenderStaging.wantsDeferral {
      let content = self.content
      _deferBuiltChildren(of: node) {
        let renderedContent = content._render(in: contentContext)
        return [legend, renderedContent].filter { !$0.isEmpty }
      }
      return node
    }
    let renderedContent = content._render(in: contentContext)
    node.children = [legend, renderedContent].filter { !$0.isEmpty }
    return node
  }
}

/// A compact semantic meter for progress, battery, and capacity UIs.  The
/// common value/range and label forms cover SwiftUI's everyday `Gauge` usage;
/// all labels remain ordinary SwiftUI views.
public nonisolated struct Gauge<Label: View>: View {
  public typealias Body = Never
  package let value: Double
  package let range: ClosedRange<Double>
  package let label: Label
  private let currentValueLabel: AnyView?
  private let minimumValueLabel: AnyView?
  private let maximumValueLabel: AnyView?

  private init(
    value: Double,
    range: ClosedRange<Double>,
    label: Label,
    currentValueLabel: AnyView? = nil,
    minimumValueLabel: AnyView? = nil,
    maximumValueLabel: AnyView? = nil
  ) {
    self.value = value
    self.range = range
    self.label = label
    self.currentValueLabel = currentValueLabel
    self.minimumValueLabel = minimumValueLabel
    self.maximumValueLabel = maximumValueLabel
  }

  public nonisolated init<V: BinaryFloatingPoint>(value: V, in range: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label) {
    self.init(value: Double(value), range: Double(range.lowerBound)...Double(range.upperBound), label: label())
  }

 nonisolated public init<V: BinaryFloatingPoint, Current: View>(
    value: V,
    in range: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> Current
  ) {
    self.init(value: Double(value), range: Double(range.lowerBound)...Double(range.upperBound), label: label(), currentValueLabel: AnyView(currentValueLabel()))
  }

 nonisolated public init<V: BinaryFloatingPoint, Current: View, Minimum: View, Maximum: View>(
    value: V,
    in range: ClosedRange<V> = 0...1,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> Current,
    @ViewBuilder minimumValueLabel: () -> Minimum,
    @ViewBuilder maximumValueLabel: () -> Maximum
  ) {
    self.init(
      value: Double(value),
      range: Double(range.lowerBound)...Double(range.upperBound),
      label: label(),
      currentValueLabel: AnyView(currentValueLabel()),
      minimumValueLabel: AnyView(minimumValueLabel()),
      maximumValueLabel: AnyView(maximumValueLabel())
    )
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["gauge-meter"]
    node.attributes["data-control-kind"] = "gauge"
    node.attributes["role"] = "meter"
    node.attributes["aria-valuemin"] = "\(range.lowerBound.clean)"
    node.attributes["aria-valuemax"] = "\(range.upperBound.clean)"
    node.attributes["aria-valuenow"] = "\(value.clean)"
    let progress = _RenderNode.element("progress")
    progress.attributes["min"] = "\(range.lowerBound.clean)"
    progress.attributes["max"] = "\(range.upperBound.clean)"
    progress.attributes["value"] = "\(min(max(value, range.lowerBound), range.upperBound).clean)"
    let renderedLabel = label._render(in: context.child(_FiberKey("label")))
    let renderedCurrent = currentValueLabel?._render(in: context.child(_FiberKey("current-value")))
    let renderedMinimum = minimumValueLabel?._render(in: context.child(_FiberKey("minimum-value")))
    let renderedMaximum = maximumValueLabel?._render(in: context.child(_FiberKey("maximum-value")))
    node.children = [renderedLabel, renderedCurrent, renderedMinimum, progress, renderedMaximum].compactMap { $0 }.filter { !$0.isEmpty }
    return node
  }
}

// MARK: - Control value bridges

private func _colorInputValue(_ color: Color) -> String {
  var value = color.cssValue.lowercased()
  // `light-dark(#light, #dark)`: the light value is what an input shows.
  if value.hasPrefix("light-dark("), let comma = value.firstIndex(of: ",") {
    value = String(value[value.index(value.startIndex, offsetBy: 11)..<comma]).filter { $0 != " " }
  }
  if value.hasPrefix("#") {
    let hex = String(value.dropFirst())
    if hex.count == 3 { return "#" + hex.map { "\($0)\($0)" }.joined() }
    if hex.count >= 6 { return "#" + String(hex.prefix(6)) }
  }
  if value.hasPrefix("rgb"), let leftParen = value.firstIndex(of: "("), let rightParen = value.firstIndex(of: ")"), leftParen < rightParen {
    var channels: [Int] = []
    for part in value[value.index(after: leftParen)..<rightParen].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).prefix(3) {
      var number = 0
      var seenDigit = false
      for character in part {
        guard let digit = character.wholeNumberValue, character.isASCII else { break }
        // Capped: the channel is clamped to 255 anyway, and a long run of digits would overflow a 32-bit Int.
        number = min(number * 10 + digit, 1_000)
        seenDigit = true
      }
      guard seenDigit else { break }
      channels.append(min(max(number, 0), 255))
    }
    if channels.count == 3 {
      let digits = Array("0123456789abcdef")
      var hex = "#"
      for channel in channels { hex.append(digits[channel / 16]); hex.append(digits[channel % 16]) }
      return hex
    }
  }
  switch value {
  case "black": return "#000000"
  case "white": return "#ffffff"
  case "red": return "#ff0000"
  case "green": return "#008000"
  case "blue": return "#0000ff"
  case "yellow": return "#ffff00"
  case "orange": return "#ffa500"
  case "purple": return "#800080"
  case "gray", "grey", "graytext": return "#808080"
  default: return "#000000"
  }
}

private func _stepperValueDescription<Value>(_ value: Value) -> String {
  #if hasFeature(Embedded)
  if let value = value as? Int { return String(value) }
  if let value = value as? Int64 { return String(value) }
  if let value = value as? UInt { return String(value) }
  if let value = value as? UInt64 { return String(value) }
  if let value = value as? Double { return String(value) }
  if let value = value as? Float { return String(value) }
  return ""
  #else
  return _swiftUIWebDescribe(value)
  #endif
}

/// Runtime values travel with tagged children until their enclosing Picker can
/// render real `<option>` elements and map browser strings back to typed values.
private struct _PickerOptionCandidate {
  let explicitToken: String?
  let tagToken: String
  let value: _RuntimeValue
  let label: String
  /// The rendered option content (Text, Image, Label...), used by styles
  /// that draw the options themselves, such as `.segmented`.
  let node: _RenderNode
}

private func _pickerOptionCandidates(in root: _RenderNode) -> [_PickerOptionCandidate] {
  var candidates: [_PickerOptionCandidate] = []
  // A loop over the nodes in document order: the options of a picker can nest any deep.
  var stack = [root]
  while let node = stack.popLast() {
    if case .element(let tag) = node.kind, tag.lowercased() == "option",
       let value = node._pickerSelectionValue {
      candidates.append(_PickerOptionCandidate(
        explicitToken: node.attributes["value"],
        tagToken: node.attributes["data-tag"] ?? "picker-option-\(candidates.count)",
        value: value,
        label: _pickerLabelText(node),
        node: node
      ))
      continue
    }
    if let value = node._pickerSelectionValue {
      candidates.append(_PickerOptionCandidate(
        explicitToken: nil,
        tagToken: node.attributes["data-tag"] ?? "picker-option-\(candidates.count)",
        value: value,
        label: _pickerLabelText(node),
        node: node
      ))
      continue
    }
    stack.append(contentsOf: node.children.reversed())
  }
  return candidates
}

/// The text of a node and what is below it, in order. A loop, not a recursion: an option can hold a view of any depth.
private func _pickerLabelText(_ node: _RenderNode) -> String {
  var result = ""
  var stack = [node]
  while let current = stack.popLast() {
    if current.kind == .text {
      result += current.text ?? ""
    } else {
      stack.append(contentsOf: current.children.reversed())
    }
  }
  return result
}

private func _selectionDescription<Value>(_ value: Value) -> String {
  if let value = value as? String { return value }
  if let value = value as? Int { return String(value) }
  if let value = value as? UInt { return String(value) }
  if let value = value as? Double { return value.clean }
  if let value = value as? Bool { return value ? "true" : "false" }
  #if !hasFeature(Embedded)
  return _swiftUIWebDescribe(value)
  #else
  return ""
  #endif
}

/// SwiftUI's axis. `Axis.Set` is the option set used by APIs that accept several axes.
public enum Axis: Int8, CaseIterable, Sendable {
  case horizontal, vertical

  public struct Set: OptionSet, Hashable, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let horizontal = Set(rawValue: 1 << 0)
    public static let vertical = Set(rawValue: 1 << 1)
  }
}

/// SwiftUI's edge. `Edge.Set` is the option set used by padding, safe-area and
/// overlay APIs.
public enum Edge: Int8, CaseIterable, Sendable {
  case top, leading, bottom, trailing

  public struct Set: OptionSet, Hashable, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public static let top = Set(rawValue: 1 << 0)
    public static let leading = Set(rawValue: 1 << 1)
    public static let bottom = Set(rawValue: 1 << 2)
    public static let trailing = Set(rawValue: 1 << 3)
    public static let horizontal: Set = [.leading, .trailing]
    public static let vertical: Set = [.top, .bottom]
    public static let all: Set = [.top, .leading, .bottom, .trailing]
  }
}

/// The top or bottom edge, for APIs that only take a vertical edge (`safeAreaBar(edge:)`, `listSectionSeparator`).
public enum VerticalEdge: Int8, CaseIterable, Hashable, Sendable {
  case top, bottom

  public struct Set: OptionSet, Hashable, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public init(_ e: VerticalEdge) { self.init(rawValue: 1 << e.rawValue) }
    public static let top = Set(.top)
    public static let bottom = Set(.bottom)
    public static let all: Set = [.top, .bottom]
  }
}

/// The leading or trailing edge, for APIs that only take a horizontal edge.
public enum HorizontalEdge: Int8, CaseIterable, Hashable, Sendable {
  case leading, trailing

  public struct Set: OptionSet, Hashable, Sendable {
    public let rawValue: Int8
    public init(rawValue: Int8) { self.rawValue = rawValue }
    public init(_ e: HorizontalEdge) { self.init(rawValue: 1 << e.rawValue) }
    public static let leading = Set(.leading)
    public static let trailing = Set(.trailing)
    public static let all: Set = [.leading, .trailing]
  }
}

extension Edge {
  init(_ edge: VerticalEdge) { self = edge == .top ? .top : .bottom }
  init(_ edge: HorizontalEdge) { self = edge == .leading ? .leading : .trailing }
}

extension Edge.Set {
  /// The one-edge set for `edge`, for internal APIs that take a set.
  init(_ edge: Edge) {
    switch edge {
    case .top: self = .top
    case .leading: self = .leading
    case .bottom: self = .bottom
    case .trailing: self = .trailing
    }
  }
}

package typealias HTML = HTMLElement

/// The source-compatible hook used by custom alignment guides.
public protocol AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> CGFloat
}

public struct HorizontalAlignment: Hashable, @unchecked Sendable {
  package let cssValue: String
  private let guide: _AlignmentGuideDefault?

  fileprivate init(cssValue: String) {
    self.cssValue = cssValue
    self.guide = nil
  }

  /// Creates a custom horizontal guide from an `AlignmentID`.
  public init(_ id: AlignmentID.Type) {
    #if hasFeature(Embedded)
    self.cssValue = "horizontal-alignment-custom"
    #else
    self.cssValue = "horizontal-alignment-\(_swiftUIWebTypeName(id))"
    #endif
    self.guide = _AlignmentGuideDefault { id.defaultValue(in: $0) }
  }

  func _defaultValue(in dimensions: ViewDimensions) -> CGFloat {
    if let guide { return guide.value(dimensions) }
    if self == .leading { return 0 }
    if self == .trailing { return dimensions.size.width }
    return dimensions.size.width / 2
  }

  public static let leading = Self(cssValue: "flex-start")
  public static let center = Self(cssValue: "center")
  public static let trailing = Self(cssValue: "flex-end")

  public static func == (lhs: HorizontalAlignment, rhs: HorizontalAlignment) -> Bool { lhs.cssValue == rhs.cssValue }
}

/// Holds a custom guide's default-value closure so the alignment types can keep synthesized `Hashable` conformance
/// (SwiftUI does not declare `hash(into:)` on them). Identity is `cssValue`, so the box never distinguishes guides.
private final class _AlignmentGuideDefault: Hashable {
  let value: (ViewDimensions) -> CGFloat
  init(_ value: @escaping (ViewDimensions) -> CGFloat) { self.value = value }
  static func == (lhs: _AlignmentGuideDefault, rhs: _AlignmentGuideDefault) -> Bool { true }
  func hash(into hasher: inout Hasher) {}
}

public struct VerticalAlignment: Hashable, @unchecked Sendable {
  package let cssValue: String
  private let guide: _AlignmentGuideDefault?

  fileprivate init(cssValue: String) {
    self.cssValue = cssValue
    self.guide = nil
  }

  /// Creates a custom vertical guide from an `AlignmentID`.
  public init(_ id: AlignmentID.Type) {
    #if hasFeature(Embedded)
    self.cssValue = "vertical-alignment-custom"
    #else
    self.cssValue = "vertical-alignment-\(_swiftUIWebTypeName(id))"
    #endif
    self.guide = _AlignmentGuideDefault { id.defaultValue(in: $0) }
  }

  func _defaultValue(in dimensions: ViewDimensions) -> CGFloat {
    if let guide { return guide.value(dimensions) }
    if self == .top { return 0 }
    if self == .bottom { return dimensions.size.height }
    if self == .firstTextBaseline || self == .lastTextBaseline { return dimensions.size.height * 0.8 }
    return dimensions.size.height / 2
  }

  public static let top = Self(cssValue: "flex-start")
  public static let center = Self(cssValue: "center")
  public static let bottom = Self(cssValue: "flex-end")
  public static let firstTextBaseline = Self(cssValue: "baseline")
  public static let lastTextBaseline = Self(cssValue: "baseline")

  public static func == (lhs: VerticalAlignment, rhs: VerticalAlignment) -> Bool { lhs.cssValue == rhs.cssValue }
}
/// Two-dimensional alignment used by stacks, frames, and overlays.  The
/// separate CSS components let the renderer preserve SwiftUI's leading/top
/// semantics even when the underlying primitive is a flex container instead
/// of a browser-specific layout object.
public struct Alignment: Hashable, Sendable {
  let cssValue: String
  let horizontalValue: String
  let verticalValue: String
  private let horizontalGuide: HorizontalAlignment?
  private let verticalGuide: VerticalAlignment?

  init(cssValue: String, horizontalValue: String, verticalValue: String, horizontalGuide: HorizontalAlignment? = nil, verticalGuide: VerticalAlignment? = nil) {
    self.cssValue = cssValue
    self.horizontalValue = horizontalValue
    self.verticalValue = verticalValue
    self.horizontalGuide = horizontalGuide
    self.verticalGuide = verticalGuide
  }

  public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
    self.cssValue = "\(vertical.cssValue) \(horizontal.cssValue)"
    self.horizontalValue = horizontal.cssValue
    self.verticalValue = vertical.cssValue
    self.horizontalGuide = (horizontal == .leading || horizontal == .center || horizontal == .trailing) ? nil : horizontal
    self.verticalGuide = (vertical == .top || vertical == .center || vertical == .bottom || vertical == .firstTextBaseline || vertical == .lastTextBaseline) ? nil : vertical
  }

  var _horizontalGuide: HorizontalAlignment? { horizontalGuide }
  var _verticalGuide: VerticalAlignment? { verticalGuide }

  /// The horizontal component, as SwiftUI's `Alignment.horizontal`.
  public var horizontal: HorizontalAlignment {
    if let horizontalGuide { return horizontalGuide }
    switch horizontalValue {
    case "start": return .leading
    case "end": return .trailing
    default: return .center
    }
  }

  /// The vertical component, as SwiftUI's `Alignment.vertical`.
  public var vertical: VerticalAlignment {
    if let verticalGuide { return verticalGuide }
    switch verticalValue {
    case "start": return .top
    case "end": return .bottom
    case "baseline": return .firstTextBaseline
    default: return .center
    }
  }

  public static let center = Self(cssValue: "center", horizontalValue: "center", verticalValue: "center")
  public static let top = Self(cssValue: "start center", horizontalValue: "center", verticalValue: "start")
  public static let bottom = Self(cssValue: "end center", horizontalValue: "center", verticalValue: "end")
  public static let leading = Self(cssValue: "center start", horizontalValue: "start", verticalValue: "center")
  public static let trailing = Self(cssValue: "center end", horizontalValue: "end", verticalValue: "center")
  public static let topLeading = Self(cssValue: "start", horizontalValue: "start", verticalValue: "start")
  public static let topTrailing = Self(cssValue: "start end", horizontalValue: "end", verticalValue: "start")
  public static let bottomLeading = Self(cssValue: "end start", horizontalValue: "start", verticalValue: "end")
  public static let bottomTrailing = Self(cssValue: "end", horizontalValue: "end", verticalValue: "end")
}
public struct TextAlignment: Hashable, Sendable { let rawValue: String; public static let leading = Self(rawValue: "left"); public static let center = Self(rawValue: "center"); public static let trailing = Self(rawValue: "right") }

private extension Double { var clean: String { Int(exactly: self).map(String.init) ?? String(self) } }

/// `type:minimum:maximum:spacing:ax:ay`. Spacing is the gap after the item
/// (`GridItem.spacing`) and `ax`/`ay` its item alignment
/// (`GridItem.alignment`); an empty field inherits the grid default.
func _semanticGridTrack(_ item: GridItem) -> String {
  let size: String
  switch item.size {
  case .fixed(let value): size = "fixed:" + String(value) + ":" + String(value)
  case .flexible(let minimum, let maximum): size = "flexible:" + String(minimum) + ":" + (maximum.isFinite ? String(maximum) : "inf")
  case .adaptive(let minimum, let maximum): size = "adaptive:" + String(minimum) + ":" + (maximum.isFinite ? String(maximum) : "inf")
  }
  let spacing = item.spacing.map { String($0) } ?? ""
  guard let alignment = item.alignment else { return size + ":" + spacing + "::" }
  let scalars = _semanticAlignment(alignment)
  return size + ":" + spacing + ":" + (scalars["data-align-x"] ?? "0.5") + ":" + (scalars["data-align-y"] ?? "0.5")
}

/// SwiftUI's default gap between grid items when `GridItem.spacing` and the
/// grid's `spacing` are nil.
let _defaultGridSpacing = 8.0

// Declared in an extension so literal initialization (`let t: Text = "x"`) stays nonisolated.
extension Text: View {}
