// SwiftUI's `TextRenderer`: a value that draws the text views below `textRenderer(_:)` itself, from their laid-out
// lines, runs and glyphs (`Text.Layout`).
//
// The browser lays the text out, so only the page knows the lines and glyphs: a text drawn by a renderer carries
// `data-text-layout`, and the geometry host (Tools/geometry-host.js, `textLayoutPayload`) measures it after layout and
// reports its layout as the `textLayout` event. Swift keeps that layout per fiber, gives it to the renderer's
// `draw(layout:in:)` with a `GraphicsContext`, and draws what the renderer records into a canvas over the text. The
// text stays in the page for layout, selection and accessibility, with its glyphs transparent. Until the first layout
// is known the text shows as usual, so nothing disappears while the page measures it.
//
// The renderer is `Animatable`: `textRenderer(_:)` is an animatable modifier, so an animation of the renderer's data
// draws every frame of it (`Animator.swift`).
//
// The wire format of `textLayout`, records separated by U+001E and fields by U+001F, numbers comma-separated:
//   x,y,width,height,truncated                         the text's box (x and y are 0), 1 when truncated
//   L  x,baseline,width,ascent,descent,leading         a line; the runs and glyphs that follow are its own
//   R  run,rtl,x,baseline,width,ascent,descent,spacing  font  color  decoration  paint
//                                                      a run: the styled span it is drawn by; the decoration is
//                                                      `lines|color|thickness|underline offset|strikethrough offset`
//                                                      (offsets from the baseline), the paint a gradient's canvas
//                                                      shading (JSON); both may be empty
//   G  x,width,character  text                         a glyph (a grapheme) of the run before it
//   S  character,width,newline                         a white-space grapheme the page laid out without a box (at a
//                                                      line's end, or a line break), with its advance
//   H  x,width,character  text                         a glyph of a line a line limit hides

// MARK: Renderer

/// A value that draws the text views of a hierarchy (`textRenderer(_:)`).
public protocol TextRenderer: Animatable {
  /// Draws `layout` into `ctx`, in the text view's coordinates.
  func draw(layout: Text.Layout, in ctx: inout GraphicsContext)
  /// The size the text view takes for `proposal`; by default, the size the text itself takes.
  func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize
  /// How far the drawing may reach outside the text view's frame.
  var displayPadding: EdgeInsets { get }
}

public extension TextRenderer {
  func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize { text.sizeThatFits(proposal) }
  var displayPadding: EdgeInsets { EdgeInsets() }
}

/// The text a `TextRenderer` sizes (`sizeThatFits(proposal:text:)`).
public struct TextProxy {
  /// The size the page laid the text out at, and the width of its widest line.
  let _size: CGSize
  let _lineCount: Int
  /// The text's graphemes with their advances and where it may break, from the page's layout: the text laid out again
  /// at another width, in at most `_lineLimit` lines.
  var _flow: _TextFlow? = nil
  var _lineLimit: Int? = nil

  /// The size the text takes for `proposal`: its graphemes, with the advances the page measured, broken into lines
  /// where the width runs out, after white space, a hyphen or an ideograph, as the browser breaks them.
  public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
    if let flow = _flow { return flow.size(fitting: proposal.width.map { Double($0) }, lineLimit: _lineLimit) }
    // Without the measured glyphs: a narrower proposal wraps it into as many more lines as that width needs.
    let width = Double(_size.width), height = Double(_size.height)
    guard let proposedWidth = proposal.width, case let proposed = Double(proposedWidth), proposed.isFinite, proposed > 0, proposed < width, width > 0 else {
      return CGSize(width: width, height: height)
    }
    var lines = width * Double(max(1, _lineCount)) / proposed
    lines.round(.up)
    let lineHeight = height / Double(max(1, _lineCount))
    return CGSize(width: proposed, height: lineHeight * lines)
  }
}

/// A value a text run carries for a `TextRenderer` (`Text.customAttribute(_:)`), read back from the layout's runs.
public protocol TextAttribute: Hashable {}

public extension Text {
  /// The text with `value` on every run of it, for a `TextRenderer` to read (`Text.Layout.Run[T.self]`). It changes
  /// nothing the text draws by itself.
  func customAttribute<T>(_ value: T) -> Text where T: TextAttribute {
    var copy = self
    copy._customAttributes.set(value)
    return copy
  }
}

/// The custom attributes of a text, by type.
struct _TextCustomAttributes {
  private var values = _TypedValueStorage<ObjectIdentifier>()
  private var hashes: [ObjectIdentifier: Int] = .init()

  var isEmpty: Bool { hashes.isEmpty }

  mutating func set<T: TextAttribute>(_ value: T) {
    let key = _storedTypeID(T.self)
    values.set(value, for: key)
    hashes[key] = value.hashValue
  }

  func value<T: TextAttribute>(_ type: T.Type) -> T? { values.value(for: _storedTypeID(type), as: type) }

  /// These attributes with `inner`'s on top: an inner text's attribute wins, as its modifiers do.
  func merging(_ inner: _TextCustomAttributes) -> _TextCustomAttributes {
    guard !inner.isEmpty else { return self }
    var merged = self
    for (key, _) in inner.hashes { merged.values._copyEntry(key, from: inner.values) }
    for (key, hash) in inner.hashes { merged.hashes[key] = hash }
    return merged
  }

  static func == (a: _TextCustomAttributes, b: _TextCustomAttributes) -> Bool { a.hashes == b.hashes }
}

// MARK: Layout

extension Text {
  /// The lines of a laid-out text, as a `TextRenderer` draws them.
  public struct Layout: RandomAccessCollection, Equatable {
    let lines: [Text.Layout.Line]
    let truncated: Bool

    init(lines: [Text.Layout.Line], truncated: Bool) {
      self.lines = lines
      self.truncated = truncated
    }

    /// Whether the text did not fit and some of it is not shown.
    public var isTruncated: Bool { truncated }
    public var startIndex: Int { 0 }
    public var endIndex: Int { lines.count }
    public subscript(index: Int) -> Text.Layout.Line { lines[index] }

    public typealias Element = Text.Layout.Line
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<Text.Layout>
    public typealias SubSequence = Slice<Text.Layout>

    public static func == (a: Text.Layout, b: Text.Layout) -> Bool { a.lines == b.lines && a.truncated == b.truncated }

    /// The position of a character in the text: the graphemes of the text, counted from 0.
    @frozen public struct CharacterIndex: Strideable, Hashable, Sendable {
      @usableFromInline let offset: Int
      @inlinable init(offset: Int) { self.offset = offset }

      public typealias Stride = Int
      @inlinable public static func < (lhs: Text.Layout.CharacterIndex, rhs: Text.Layout.CharacterIndex) -> Bool { lhs.offset < rhs.offset }
      @inlinable public func advanced(by n: Int) -> Text.Layout.CharacterIndex { CharacterIndex(offset: offset + n) }
      @inlinable public func distance(to other: Text.Layout.CharacterIndex) -> Int { other.offset - offset }
    }

    /// Where a line, run or glyph sits: its baseline origin, its advance and how far it reaches above and below the
    /// baseline.
    @frozen public struct TypographicBounds: Equatable, Sendable {
      public var origin: CGPoint
      public var width: CGFloat
      public var ascent: CGFloat
      public var descent: CGFloat
      public var leading: CGFloat

      @inlinable public init() {
        origin = CGPoint(x: 0, y: 0)
        width = 0
        ascent = 0
        descent = 0
        leading = 0
      }

      @inlinable init(origin: CGPoint, width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        self.origin = origin
        self.width = width
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
      }

      /// The box from the top of the ascent to the bottom of the descent.
      public var rect: CGRect { CGRect(x: origin.x, y: origin.y - ascent, width: width, height: ascent + descent) }

      public static func == (a: Text.Layout.TypographicBounds, b: Text.Layout.TypographicBounds) -> Bool {
        a.origin == b.origin && a.width == b.width && a.ascent == b.ascent && a.descent == b.descent && a.leading == b.leading
      }
    }

    /// One line of the text: its runs, left to right.
    public struct Line: RandomAccessCollection, Equatable {
      let runs: [Text.Layout.Run]
      let bounds: Text.Layout.TypographicBounds

      /// The line's baseline origin, in the text's coordinates.
      public var origin: CGPoint

      init(runs: [Text.Layout.Run], bounds: Text.Layout.TypographicBounds) {
        self.runs = runs
        self.bounds = bounds
        origin = bounds.origin
      }

      public var startIndex: Int { 0 }
      public var endIndex: Int { runs.count }
      public subscript(index: Int) -> Text.Layout.Run { runs[index] }
      public var typographicBounds: Text.Layout.TypographicBounds {
        var moved = bounds
        moved.origin = origin
        return moved
      }

      public typealias Element = Text.Layout.Run
      public typealias Index = Int
      public typealias Indices = Range<Int>
      public typealias Iterator = IndexingIterator<Text.Layout.Line>
      public typealias SubSequence = Slice<Text.Layout.Line>

      public static func == (lhs: Text.Layout.Line, rhs: Text.Layout.Line) -> Bool {
        lhs.runs == rhs.runs && lhs.bounds == rhs.bounds && lhs.origin == rhs.origin
      }
    }

    /// A stretch of a line drawn in one style: its glyphs.
    public struct Run: RandomAccessCollection, Equatable {
      let glyphs: [_TextGlyph]
      let bounds: Text.Layout.TypographicBounds
      let style: _TextRunStyle
      let attributes: _TextCustomAttributes

      init(glyphs: [_TextGlyph], bounds: Text.Layout.TypographicBounds, style: _TextRunStyle, attributes: _TextCustomAttributes) {
        self.glyphs = glyphs
        self.bounds = bounds
        self.style = style
        self.attributes = attributes
      }

      public var startIndex: Int { 0 }
      public var endIndex: Int { glyphs.count }
      /// The glyph at `index`, as a slice of one.
      public subscript(index: Int) -> Text.Layout.RunSlice { Text.Layout.RunSlice(run: self, indices: index..<(index + 1)) }
      public subscript(bounds: Range<Int>) -> Text.Layout.RunSlice { Text.Layout.RunSlice(run: self, indices: bounds) }
      /// The value of the custom attribute `key` the run's text carries (`Text.customAttribute(_:)`).
      public subscript<T>(key: T.Type) -> T? where T: TextAttribute { attributes.value(key) }

      public var layoutDirection: LayoutDirection { style.rightToLeft ? .rightToLeft : .leftToRight }
      public var typographicBounds: Text.Layout.TypographicBounds { bounds }
      public var characterIndices: [Text.Layout.CharacterIndex] { glyphs.map { CharacterIndex(offset: $0.character) } }

      public typealias Element = Text.Layout.RunSlice
      public typealias Index = Int
      public typealias Indices = Range<Int>
      public typealias Iterator = IndexingIterator<Text.Layout.Run>
      public typealias SubSequence = Text.Layout.RunSlice

      public static func == (lhs: Text.Layout.Run, rhs: Text.Layout.Run) -> Bool {
        lhs.glyphs == rhs.glyphs && lhs.bounds == rhs.bounds && lhs.style == rhs.style && lhs.attributes == rhs.attributes
      }

      /// The bounds of the glyphs in `range`: their advance, at the run's baseline and height.
      func bounds(of range: Range<Int>) -> Text.Layout.TypographicBounds {
        guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= glyphs.count else {
          return Text.Layout.TypographicBounds(origin: CGPoint(x: bounds.origin.x, y: bounds.origin.y), width: 0, ascent: bounds.ascent, descent: bounds.descent, leading: bounds.leading)
        }
        var left = Double.infinity, right = -Double.infinity
        for glyph in glyphs[range] {
          left = Swift.min(left, glyph.x)
          right = Swift.max(right, glyph.x + glyph.width)
        }
        return Text.Layout.TypographicBounds(origin: CGPoint(x: left, y: bounds.origin.y), width: CGFloat(right - left), ascent: bounds.ascent, descent: bounds.descent, leading: bounds.leading)
      }
    }

    /// Some of the glyphs of a run.
    public struct RunSlice: RandomAccessCollection, Equatable {
      public var run: Text.Layout.Run
      public var indices: Range<Int>

      public init(run: Text.Layout.Run, indices: Range<Int>) {
        self.run = run
        self.indices = indices
      }

      public var startIndex: Int { indices.lowerBound }
      public var endIndex: Int { indices.upperBound }
      public subscript(index: Int) -> Text.Layout.RunSlice { Text.Layout.RunSlice(run: run, indices: index..<(index + 1)) }
      public subscript(bounds: Range<Int>) -> Text.Layout.RunSlice { Text.Layout.RunSlice(run: run, indices: bounds) }
      public subscript<T>(key: T.Type) -> T? where T: TextAttribute { run[key] }

      public var typographicBounds: Text.Layout.TypographicBounds { run.bounds(of: indices) }
      public var characterIndices: [Text.Layout.CharacterIndex] {
        indices.compactMap { $0 >= 0 && $0 < run.glyphs.count ? CharacterIndex(offset: run.glyphs[$0].character) : nil }
      }

      public typealias Element = Text.Layout.RunSlice
      public typealias Index = Int
      public typealias Indices = Range<Int>
      public typealias Iterator = IndexingIterator<Text.Layout.RunSlice>
      public typealias SubSequence = Text.Layout.RunSlice

      public static func == (a: Text.Layout.RunSlice, b: Text.Layout.RunSlice) -> Bool { a.run == b.run && a.indices == b.indices }
    }

    /// How `GraphicsContext` draws a line, run or slice.
    @frozen public struct DrawingOptions: OptionSet, Sendable {
      public let rawValue: UInt32
      @inlinable public init(rawValue: UInt32) { self.rawValue = rawValue }
      /// Glyph positions are not rounded to the device's pixels. Canvas text is never rounded, so this changes nothing.
      @inlinable public static var disablesSubpixelQuantization: Text.Layout.DrawingOptions { DrawingOptions(rawValue: 1 << 0) }

      public typealias ArrayLiteralElement = Text.Layout.DrawingOptions
      public typealias Element = Text.Layout.DrawingOptions
      public typealias RawValue = UInt32
    }
  }
}

/// A glyph of a run: a grapheme, where the page drew it.
struct _TextGlyph: Equatable {
  var x: Double
  var width: Double
  var character: Int
  var text: String
  /// The ellipsis the page draws where it cuts a text: drawn with the layout, but not a character of the text.
  var synthetic = false
}

/// What a run is drawn with: the page's CSS font, color and letter spacing, its direction, its underline or
/// strikethrough, and the gradient it is painted with (a canvas shading, empty for its color).
struct _TextRunStyle: Equatable {
  var font: String
  var color: String
  var spacing: Double
  var rightToLeft: Bool
  var decoration: _TextDecoration? = nil
  var paint: String = ""
}

/// The lines `underline` and `strikethrough` draw through a run: where, from its baseline, how thick, in what color.
struct _TextDecoration: Equatable {
  var underline: Bool
  var strikethrough: Bool
  var color: String
  var thickness: Double
  var underlineOffset: Double
  var strikethroughOffset: Double

  /// `lines|color|thickness|underline offset|strikethrough offset`, as the page measures it.
  init?(decoding text: String) {
    let fields = _textLayoutSplit(Array(text.utf8), separator: UInt8(ascii: "|"))
    guard fields.count == 5 else { return nil }
    let lines = _textLayoutSplit(fields[0], separator: UInt8(ascii: " ")).map { String(decoding: $0, as: UTF8.self) }
    underline = lines.contains("underline")
    strikethrough = lines.contains("line-through")
    color = String(decoding: fields[1], as: UTF8.self)
    let numbers = fields[2...].map { Double(String(decoding: $0, as: UTF8.self)) }
    guard underline || strikethrough, let thickness = numbers[0], let under = numbers[1], let through = numbers[2],
          thickness.isFinite, under.isFinite, through.isFinite else { return nil }
    self.thickness = thickness
    underlineOffset = under
    strikethroughOffset = through
  }
}

// MARK: Drawing

public extension GraphicsContext {
  /// Draws the glyphs of `line` where the layout put them.
  mutating func draw(_ line: Text.Layout.Line, options: Text.Layout.DrawingOptions = .init()) {
    let dx = Double(line.origin.x - line.bounds.origin.x), dy = Double(line.origin.y - line.bounds.origin.y)
    for run in line.runs { _draw(run, range: 0..<run.glyphs.count, dx: dx, dy: dy) }
  }

  /// Draws the glyphs of `run` where the layout put them.
  mutating func draw(_ run: Text.Layout.Run, options: Text.Layout.DrawingOptions = .init()) {
    _draw(run, range: 0..<run.glyphs.count, dx: 0, dy: 0)
  }

  /// Draws the glyphs of `slice` where the layout put them.
  mutating func draw(_ slice: Text.Layout.RunSlice, options: Text.Layout.DrawingOptions = .init()) {
    _draw(slice.run, range: slice.indices, dx: 0, dy: 0)
  }

  /// The glyphs of `range`, as one string from the first one's origin: the canvas shapes them as the page did.
  private mutating func _draw(_ run: Text.Layout.Run, range: Range<Int>, dx: Double, dy: Double) {
    let lower = max(0, range.lowerBound), upper = min(run.glyphs.count, range.upperBound)
    guard lower < upper else { return }
    var text = ""
    var left = Double.infinity, right = -Double.infinity
    for glyph in run.glyphs[lower..<upper] {
      text += glyph.text
      left = min(left, glyph.x)
      right = max(right, glyph.x + glyph.width)
    }
    let style = run.style
    let baseline = Double(run.bounds.origin.y) + dy
    _drawGlyphs(text, x: (style.rightToLeft ? right : left) + dx, y: baseline, font: style.font, color: style.color, spacing: style.spacing, rightToLeft: style.rightToLeft, paint: style.paint)
    // Its underline and strikethrough run under the glyphs drawn, as the page draws them.
    guard let decoration = style.decoration else { return }
    if decoration.underline {
      _drawTextDecoration(x0: left + dx, x1: right + dx, y: baseline + decoration.underlineOffset, thickness: decoration.thickness, color: decoration.color)
    }
    if decoration.strikethrough {
      _drawTextDecoration(x0: left + dx, x1: right + dx, y: baseline + decoration.strikethroughOffset, thickness: decoration.thickness, color: decoration.color)
    }
  }
}

// MARK: View

public extension View {
  /// Draws the text views in this view with `renderer`.
  nonisolated func textRenderer<T>(_ renderer: T) -> some View where T: TextRenderer {
    _modified(_TextRendererModifier(renderer: renderer))
  }
}

/// `textRenderer(_:)`: the renderer for the text views below, animated with the renderer's data.
nonisolated struct _TextRendererModifier<Renderer: TextRenderer>: ViewModifier, Animatable {
  var renderer: Renderer

  var animatableData: Renderer.AnimatableData {
    get { renderer.animatableData }
    set { renderer.animatableData = newValue }
  }

  static var _swiftUIWebAnimates: Bool { Renderer._swiftUIWebAnimates }

  @MainActor func _modifyContext(_ context: inout _RenderContext) {
    Text._installMeasuredRendering()
    context.environment._textRenderer = _TextRendererBox(renderer)
  }
}

/// A renderer, erased: what the text views below draw with.
final class _TextRendererBox {
  let draw: (Text.Layout, inout GraphicsContext) -> Void
  let size: (ProposedViewSize, TextProxy) -> CGSize
  let padding: EdgeInsets
  /// Draws a measured text with this renderer (`Text._drawRendered`). Only `textRenderer(_:)` makes a box, so the canvas
  /// a renderer draws on is part of a release only when the application draws text with a renderer.
  let render: @MainActor (_TextRendererBox, Text, _RenderNode, _MeasuredTextLayout, Text.Layout, _RenderContext) -> _RenderNode

  init<Renderer: TextRenderer>(_ renderer: Renderer) {
    draw = { layout, context in renderer.draw(layout: layout, in: &context) }
    size = { proposal, text in renderer.sizeThatFits(proposal: proposal, text: text) }
    padding = renderer.displayPadding
    render = { box, text, node, measured, layout, context in
      text._drawRendered(by: box, node: node, measured: measured, layout: layout, context: context)
    }
  }
}

private struct _TextRendererKey: EnvironmentKey {
  static var defaultValue: _TextRendererBox? { nil }
}

private struct _PaintClipsToTextKey: EnvironmentKey {
  static var defaultValue: Bool { false }
}

extension EnvironmentValues {
  /// Whether a view above paints its foreground style clipped to the text of its subtree (a gradient
  /// `foregroundStyle` on a stack): that paint shows through the glyphs of every text here.
  var _paintClipsToText: Bool {
    get { self[_PaintClipsToTextKey.self] }
    set { self[_PaintClipsToTextKey.self] = newValue }
  }

  /// The renderer `textRenderer(_:)` above set for the text views here.
  var _textRenderer: _TextRendererBox? {
    get { self[_TextRendererKey.self] }
    set { self[_TextRendererKey.self] = newValue }
  }
}

extension Text {
  /// `_renderMeasured`, which `_render` calls through this value rather than by name: the views that need a measured text
  /// (`textRenderer(_:)`, a reader of `Text.LayoutKey`) install it before they set the environment that asks for it, so
  /// an application that uses neither does not carry the measurement (and the canvas behind a renderer) in a release.
  @MainActor static var _measuredRendering: ((Text, _TextRendererBox?, _RenderContext) -> _RenderNode)?

  @MainActor static func _installMeasuredRendering() {
    guard _measuredRendering == nil else { return }
    _measuredRendering = { text, renderer, context in text._renderMeasured(drawnBy: renderer, in: context) }
  }

  /// The text measured by the page: as it renders by itself, with the drawing of `renderer` over it once the page
  /// reported its layout, and that layout given to the views above as `Text.LayoutKey` when a reader there asked.
  @MainActor func _renderMeasured(drawnBy renderer: _TextRendererBox?, in context: _RenderContext) -> _RenderNode {
    var plain = context
    plain.environment._textRenderer = nil
    plain.environment._publishesTextLayout = false
    let rendered = _renderPlain(in: plain)
    // An image alone in a text has no glyphs to draw.
    if _textRuns.isEmpty && _inlineImage != nil { return rendered }
    let node: _RenderNode
    if rendered.kind == .text {
      // A text leaf with a canvas in it: the same span the text node becomes, holding its text.
      node = _RenderNode.element("span")
      node.classes = rendered.classes
      node.attributes = rendered.attributes
      node.styles = rendered.styles
      node.children = [_RenderNode.text(rendered.text ?? "")]
      node.attributes["data-layout-kind"] = "intrinsic"
      node.attributes["data-layout-leaf"] = "text"
    } else {
      node = rendered
    }
    var attributes: [_TextCustomAttributes] = []
    _indexRuns(node: node, inherited: _TextCustomAttributes(), into: &attributes)
    node.attributes["data-text-layout"] = "true"

    let key = context._compactPathID + "#text-layout"
    let store = context.stateStore
    let ownerToken = context._renderOwnerToken
    node.events["textLayout"] = _EventHandler(name: "textLayout", action: { raw in
      guard let measured = _MeasuredTextLayout(decoding: raw), store._textLayouts[key] != measured else { return }
      store._textLayouts[key] = measured
      if let ownerToken { store._ownerObservationDidChange(ownerToken) }
    })
    let publishes = context.environment._publishesTextLayout
    if publishes {
      _renderRegistersWithAncestors()
      _measureWindowFrame(of: node, key: key + "#origin", store: store, owner: ownerToken, reader: context._preferenceLayerOwner)
    }
    guard let measured = store._textLayouts[key] else { return node }

    let layout = measured.layout(attributes: attributes)
    if publishes {
      let frame = _anchorFrame(key: key + "#origin", store: store)
      context.preferenceStore.write([Text.LayoutKey.AnchoredLayout(origin: Anchor<CGPoint>.Source.topLeading._make(frame), layout: layout)], for: Text.LayoutKey.self)
    }
    guard let renderer else { return node }
    return renderer.render(renderer, self, node, measured, layout, context)
  }

  /// The measured text `node` with `renderer`'s drawing over it, on a canvas of the laid-out text's size.
  @MainActor func _drawRendered(by renderer: _TextRendererBox, node: _RenderNode, measured: _MeasuredTextLayout, layout: Text.Layout, context: _RenderContext) -> _RenderNode {
    let proxy = TextProxy(_size: measured.contentSize, _lineCount: measured.lines.count, _flow: measured.flow, _lineLimit: context.environment.lineLimit)
    let proposal = context._layoutProposal ?? .unspecified
    let natural = proxy.sizeThatFits(proposal)
    let size = renderer.size(proposal, proxy)
    let resized = abs(Double(size.width - natural.width)) > 0.5 || abs(Double(size.height - natural.height)) > 0.5
    // The glyphs the page draws give way to the renderer's: transparent, without decorations or a painted
    // background clipped to them, where the text still lays out, selects and reads.
    // The runs may be nodes a render kept from before (a run that did not change): the cleared ones are copies.
    node.children = node.children.map { $0.clone() }
    _clearGlyphPaint(node)
    node.styles["position"] = "relative"
    let padding = renderer.padding
    let canvasSize = CGSize(
      width: Double(measured.size.width) + padding.leading + padding.trailing,
      height: Double(measured.size.height) + padding.top + padding.bottom)
    let canvas = _textRendererCanvas(size: canvasSize, origin: CGPoint(x: padding.leading, y: padding.top), environment: context.environment) { graphics in
      renderer.draw(layout, &graphics)
    }
    if context.environment._paintClipsToText {
      // A paint above clipped to text shows through every glyph of its subtree, transparent or in a layer of its own:
      // only hidden glyphs stay out of it. The text still lays out; the drawing shows and reads it.
      node.styles["visibility"] = "hidden"
      canvas.styles["visibility"] = "visible"
      canvas.attributes["aria-hidden"] = nil
      canvas.attributes["role"] = "img"
      canvas.attributes["aria-label"] = _renderedString(node)
    }
    node.children = node.children + [canvas]
    // A renderer that sizes the text otherwise gives it a frame of that size, which the text lays out in from its
    // top-leading corner, as a frame the layout knows (a text leaf is sized by its glyphs).
    if resized {
      var frameContext = context
      _frameModifier(width: Double(size.width), height: Double(size.height), alignment: .topLeading)._apply(to: node, context: &frameContext)
    }
    return node
  }

  /// Numbers the leaves of the rendered text in the order the page reads them (`data-text-run`), and records the custom
  /// attributes each one carries, its own over the ones of the texts around it.
  @MainActor func _indexRuns(node: _RenderNode, inherited: _TextCustomAttributes, into table: inout [_TextCustomAttributes]) {
    let attributes = inherited.merging(_customAttributes)
    guard !_textRuns.isEmpty else {
      node.attributes["data-text-run"] = String(table.count)
      table.append(attributes)
      return
    }
    let children = node.children
    for (index, run) in _textRuns.enumerated() where index < children.count {
      var child = children[index]
      // A linked run is an anchor around its span.
      if child.kind == .element("a"), let inner = child.children.first { child = inner }
      run._indexRuns(node: child, inherited: attributes, into: &table)
    }
  }
}

/// The characters a rendered text shows, in the order the page reads them.
@MainActor private func _renderedString(_ node: _RenderNode) -> String {
  if node.kind == .text { return node.text ?? "" }
  return node.children.map { _renderedString($0) }.joined()
}

/// Makes the glyphs of a text leaf and its runs transparent, the decorations and clipped paints too. What they were
/// painted with stays on the node for the page to measure (`data-text-paint-*`), so the renderer draws with it.
@MainActor private func _clearGlyphPaint(_ node: _RenderNode) {
  // A styled run is a text leaf with styles of its own (a span); a bare text leaf has nothing to clear.
  if node.kind != .text || !node.styles.isEmpty {
    node.styles["-webkit-text-fill-color"] = "transparent"
    if let line = node.styles["text-decoration-line"], line != "none" {
      node.attributes["data-text-paint-decoration"] = node.styles["text-decoration-color"] ?? "currentcolor"
    }
    node.styles["text-decoration-color"] = "transparent"
    if node.styles["background-clip"] != nil || node.styles["-webkit-background-clip"] != nil {
      if let image = node.styles["background-image"], image != "none" { node.attributes["data-text-paint-image"] = image }
      node.styles["background-image"] = "none"
    }
  }
  for child in node.children { _clearGlyphPaint(child) }
}

// MARK: Measured layout

/// A text layout as the page measured it (the `textLayout` event), before the custom attributes of its runs.
struct _MeasuredTextLayout: Equatable {
  struct Line: Equatable {
    var x, baseline, width, ascent, descent, leading: Double
    var runs: [Run]
  }

  struct Run: Equatable {
    var index: Int
    var x, baseline, width, ascent, descent: Double
    var style: _TextRunStyle
    var glyphs: [_TextGlyph]
  }

  /// A white-space grapheme the page laid out without a box: its advance, and whether it breaks the line.
  struct Gap: Equatable {
    var character: Int
    var width: Double
    var newline: Bool
  }

  var size: CGSize
  var truncated: Bool
  var lines: [Line]
  var gaps: [Gap] = []
  /// The glyphs of the lines a line limit hides.
  var hidden: [_TextGlyph] = []

  /// The text's graphemes in reading order, for laying it out again at another width (`TextProxy`).
  var flow: _TextFlow? {
    guard let first = lines.first else { return nil }
    var entries: [(character: Int, piece: _TextFlow.Piece, ideograph: Bool)] = []
    for line in lines {
      for run in line.runs {
        for glyph in run.glyphs where !glyph.synthetic {
          let scalar = glyph.text.unicodeScalars.first?.value ?? 0
          let space = !glyph.text.isEmpty && glyph.text.unicodeScalars.allSatisfy { $0.value == 0x20 || $0.value == 0x09 || $0.value == 0x0A }
          let ideograph = (0x2E80...0x9FFF).contains(scalar) || (0xAC00...0xD7AF).contains(scalar) || (0xF900...0xFAFF).contains(scalar) || (0xFF00...0xFFEF).contains(scalar)
          let breaks = space || glyph.text == "-" || ideograph
          entries.append((glyph.character, _TextFlow.Piece(width: glyph.width, breakAfter: breaks, space: space, newline: false), ideograph))
        }
      }
    }
    for glyph in hidden {
      let space = !glyph.text.isEmpty && glyph.text.unicodeScalars.allSatisfy { $0.value == 0x20 || $0.value == 0x09 || $0.value == 0x0A }
      entries.append((glyph.character, _TextFlow.Piece(width: glyph.width, breakAfter: space || glyph.text == "-", space: space, newline: false), false))
    }
    for gap in gaps {
      entries.append((gap.character, _TextFlow.Piece(width: gap.width, breakAfter: true, space: true, newline: gap.newline), false))
    }
    _stableSort(&entries) { $0.character < $1.character }
    var pieces: [_TextFlow.Piece] = []
    pieces.reserveCapacity(entries.count)
    for entry in entries {
      // A line may also break before an ideograph.
      if entry.ideograph, !pieces.isEmpty { pieces[pieces.count - 1].breakAfter = true }
      pieces.append(entry.piece)
    }
    var firstLine = first.baseline + first.descent + first.leading / 2
    let lineHeight = lines.count > 1 ? (lines[lines.count - 1].baseline - first.baseline) / Double(_lineAdvances()) : first.ascent + first.descent + first.leading
    // A text that begins with newlines: the first line the page reports is below them, so its baseline has their advances in it,
    // and the reflow, which walks the newlines as gaps, would count them a second time.
    var firstCharacter = Int.max
    for run in first.runs { for glyph in run.glyphs where !glyph.synthetic { firstCharacter = min(firstCharacter, glyph.character) } }
    // A first line that is the ellipsis alone (no glyph fits beside it): the ellipsis stands where its first character was.
    if firstCharacter == Int.max { for run in first.runs { for glyph in run.glyphs { firstCharacter = min(firstCharacter, glyph.character) } } }
    let leadingBreaks = gaps.reduce(0) { $0 + ($1.newline && $1.character < firstCharacter ? 1 : 0) }
    firstLine -= Double(leadingBreaks) * lineHeight
    return _TextFlow(pieces: pieces, firstLine: firstLine, lineHeight: lineHeight)
  }

  /// How many line advances lie between the first line and the last. The page reports a line only where it has glyphs, so a
  /// blank line between two of them (`a\n\nb`) is an advance without a record: the newlines between a line's last character
  /// and the next line's first count, and a soft wrap, which has none, is one.
  func _lineAdvances() -> Int {
    var ranges: [(first: Int, last: Int)] = []
    for line in lines {
      var first = Int.max, last = Int.min
      for run in line.runs { for glyph in run.glyphs where !glyph.synthetic { first = min(first, glyph.character); last = max(last, glyph.character) } }
      if first <= last { ranges.append((first, last)) }
    }
    // A line with no glyph of its own: count the lines, as before.
    guard ranges.count == lines.count else { return lines.count - 1 }
    // The newline gaps' characters, sorted once, so each pair of lines counts its newlines by binary search.
    var newlines = gaps.compactMap { $0.newline ? $0.character : nil }
    newlines.sort()
    // The index of the first newline at or after `value`.
    func firstNewline(atLeast value: Int) -> Int {
      var low = 0, high = newlines.count
      while low < high {
        let middle = (low + high) / 2
        if newlines[middle] < value { low = middle + 1 } else { high = middle }
      }
      return low
    }
    var advances = 0
    for index in 1..<ranges.count {
      // Newlines strictly between the last character of the line before and the first character of this one.
      let after = firstNewline(atLeast: ranges[index - 1].last + 1)
      let before = firstNewline(atLeast: ranges[index].first)
      advances += max(1, before - after)
    }
    return max(1, advances)
  }

  /// The width of the widest line and the height down to the last line's descent: the size of the text itself.
  var contentSize: CGSize {
    var width = 0.0, height = 0.0
    for line in lines {
      width = max(width, line.x + line.width)
      height = max(height, line.baseline + line.descent + line.leading / 2)
    }
    if lines.isEmpty { return size }
    return CGSize(width: width, height: height)
  }

  init?(decoding raw: String) {
    let records = _textLayoutSplit(Array(raw.utf8), separator: 0x1E)
    guard let first = records.first else { return nil }
    let head = _textLayoutNumbers(first)
    guard head.count >= 4 else { return nil }
    size = CGSize(width: head[2], height: head[3])
    truncated = head.count > 4 && head[4] != 0
    lines = []
    for record in records.dropFirst() {
      let fields = _textLayoutSplit(record, separator: 0x1F)
      guard fields.count >= 2, fields[0].count == 1 else { continue }
      let numbers = _textLayoutNumbers(fields[1])
      switch fields[0][0] {
      case UInt8(ascii: "L"):
        guard numbers.count == 6 else { return nil }
        lines.append(Line(x: numbers[0], baseline: numbers[1], width: numbers[2], ascent: numbers[3], descent: numbers[4], leading: numbers[5], runs: []))
      case UInt8(ascii: "R"):
        guard numbers.count == 8, fields.count >= 4, !lines.isEmpty else { return nil }
        // A run index the page wrote out of range is skipped, not converted: `Int(_:)` of such a Double traps.
        guard let runIndex = Int(exactly: numbers[0]) else { continue }
        var style = _TextRunStyle(font: String(decoding: fields[2], as: UTF8.self), color: String(decoding: fields[3], as: UTF8.self), spacing: numbers[7], rightToLeft: numbers[1] != 0)
        if fields.count > 4, !fields[4].isEmpty { style.decoration = _TextDecoration(decoding: String(decoding: fields[4], as: UTF8.self)) }
        if fields.count > 5 { style.paint = String(decoding: fields[5], as: UTF8.self) }
        lines[lines.count - 1].runs.append(Run(index: runIndex, x: numbers[2], baseline: numbers[3], width: numbers[4], ascent: numbers[5], descent: numbers[6], style: style, glyphs: []))
      case UInt8(ascii: "H"):
        guard numbers.count == 3, fields.count == 3 else { return nil }
        guard let character = Int(exactly: numbers[2]) else { continue }
        hidden.append(_TextGlyph(x: numbers[0], width: numbers[1], character: character, text: String(decoding: fields[2], as: UTF8.self)))
      case UInt8(ascii: "S"):
        guard numbers.count == 3 else { return nil }
        guard let character = Int(exactly: numbers[0]) else { continue }
        gaps.append(Gap(character: character, width: numbers[1], newline: numbers[2] != 0))
      case UInt8(ascii: "G"):
        guard numbers.count == 3 || numbers.count == 4, fields.count == 3, let line = lines.indices.last, let run = lines[line].runs.indices.last else { return nil }
        guard let character = Int(exactly: numbers[2]) else { continue }
        lines[line].runs[run].glyphs.append(_TextGlyph(x: numbers[0], width: numbers[1], character: character, text: String(decoding: fields[2], as: UTF8.self), synthetic: numbers.count == 4 && numbers[3] != 0))
      default:
        continue
      }
    }
  }

  /// The layout a renderer draws, each run with the custom attributes of the leaf the page drew it from.
  func layout(attributes: [_TextCustomAttributes]) -> Text.Layout {
    Text.Layout(lines: lines.map { line in
      let runs = line.runs.map { run in
        Text.Layout.Run(
          glyphs: run.glyphs,
          bounds: Text.Layout.TypographicBounds(origin: CGPoint(x: run.x, y: run.baseline), width: CGFloat(run.width), ascent: CGFloat(run.ascent), descent: CGFloat(run.descent), leading: 0),
          style: run.style,
          attributes: run.index >= 0 && run.index < attributes.count ? attributes[run.index] : _TextCustomAttributes())
      }
      return Text.Layout.Line(runs: runs, bounds: Text.Layout.TypographicBounds(origin: CGPoint(x: line.x, y: line.baseline), width: CGFloat(line.width), ascent: CGFloat(line.ascent), descent: CGFloat(line.descent), leading: CGFloat(line.leading)))
    }, truncated: truncated)
  }
}

func _textLayoutSplit(_ bytes: [UInt8], separator: UInt8) -> [[UInt8]] {
  var result: [[UInt8]] = []
  var current: [UInt8] = []
  for byte in bytes {
    if byte == separator { result.append(current); current = [] } else { current.append(byte) }
  }
  result.append(current)
  return result
}

/// Comma-separated finite numbers; a malformed field rejects the list.
private func _textLayoutNumbers(_ bytes: [UInt8]) -> [Double] {
  var values: [Double] = []
  for field in _textLayoutSplit(bytes, separator: UInt8(ascii: ",")) {
    guard !field.isEmpty, let value = Double(String(decoding: field, as: UTF8.self)), value.isFinite else { return [] }
    values.append(value)
  }
  return values
}

/// A text as a sequence of graphemes with the advances the page measured, laid out again at a width by breaking lines
/// greedily where the page would: after white space, a hyphen or an ideograph, and at a line break. A line's trailing
/// white space hangs past the width, and a word longer than the width breaks where it runs out.
struct _TextFlow: Equatable {
  struct Piece: Equatable {
    var width: Double
    var breakAfter: Bool
    var space: Bool
    var newline: Bool
  }

  var pieces: [Piece]
  /// From the text's top to the bottom of its first line, and from one baseline to the next.
  var firstLine: Double
  var lineHeight: Double

  /// The size of the text laid out at `width` (unlimited when nil): its widest line, and its lines' height. With a line
  /// limit, the lines past it are left out, and a text they truncate takes the whole width it was given.
  func size(fitting width: Double?, lineLimit: Int? = nil) -> CGSize {
    let limit = width.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? Double.infinity
    var lines = 0, widest = 0.0, start = 0
    repeat {
      var used = 0.0, visible = 0.0, end = start
      var lastBreak = -1, visibleAtBreak = 0.0
      while end < pieces.count {
        let piece = pieces[end]
        if piece.newline { end += 1; break }
        if !piece.space, visible > 0, used + piece.width > limit + 0.01 {
          if lastBreak >= start { end = lastBreak + 1; visible = visibleAtBreak }
          break
        }
        used += piece.width
        if !piece.space { visible = used }
        if piece.breakAfter { lastBreak = end; visibleAtBreak = visible }
        end += 1
      }
      if let lineLimit, lines == Swift.max(1, lineLimit) {
        // A line past the limit: the text is truncated, and its last line runs to the edge with an ellipsis.
        if limit.isFinite { widest = limit }
        break
      }
      lines += 1
      widest = Swift.max(widest, visible)
      start = end
    } while start < pieces.count
    return CGSize(width: widest, height: firstLine + Double(lines - 1) * lineHeight)
  }
}
