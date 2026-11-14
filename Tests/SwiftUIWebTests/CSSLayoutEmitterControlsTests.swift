import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Browser) @_spi(Renderer) @testable import SwiftUIWebBrowser

/// The blocks `_CSSLayoutEmitter` writes for the controls whose size the browser does not give them: a Divider, a linear
/// ProgressView, a Slider, a Gauge and a TextEditor. The page's mapper (`Tools/css-layout.js`) writes the same blocks
/// (`Tools/test-css-layout-fixtures-browser.mjs` checks them in `EmbeddedControlsFixture`); Apple's frames of the same
/// trees are in `Tests/LayoutConformance/apple-macos-css-extra.json`.
@MainActor
struct CSSLayoutEmitterControlsTests {
  /// The declarations the emitter writes for each element with the tag `tag` (and the class `className`, if given) in `view`, in
  /// tree order; nil when CSS does not lay `view` out.
  private func blocks<V: View>(of view: V, tag: String, className: String? = nil) -> [String]? {
    let tree = FiberTree(view, deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    guard !emitter.roots.isEmpty else { return nil }
    let rules = emitter.resolvedRules()
    var found: [String] = [], stack = [tree.root]
    while let fiber = stack.popLast() {
      if case .element(let name) = fiber.renderNode.kind, name == tag, className.map({ fiber.renderNode.classes.contains($0) }) ?? true, let id = emitter.assigned[ObjectIdentifier(fiber)],
         let line = rules.split(separator: "\n").first(where: { $0.hasPrefix(".sl\(id){") }) {
        found.append(String(line))
      }
      stack.append(contentsOf: fiber.children.reversed())
    }
    return found
  }

  private func one<V: View>(_ view: V, tag: String, className: String? = nil) -> String {
    guard let all = blocks(of: view, tag: tag, className: className), all.count == 1 else { Issue.record("CSS does not lay out a single <\(tag)>"); return "" }
    return all[0]
  }

  /// A Divider in a VStack runs across it: as wide as the stack, a point thick.
  @Test
  func aDividerInAVStackTakesTheStacksWidth() {
    let rule = one(VStack(alignment: .leading) { Text("Above"); Divider(); Text("Below") }.frame(width: 200), tag: "hr")
    #expect(rule.contains("height:1px"), "a point thick")
    #expect(rule.contains("flex:0 0 1px"))
    #expect(rule.contains("align-self:stretch"), "as wide as the stack")
    #expect(!rule.contains("border-left-width"), "it keeps the stylesheet's border along its top")
  }

  /// In an HStack it runs vertically, as tall as the row: the line moves to its leading edge.
  @Test
  func aDividerInAnHStackTakesTheRowsHeight() {
    let rule = one(HStack { Text("Left"); Divider(); Text("Right") }.frame(width: 200, height: 40), tag: "hr")
    #expect(rule.contains("width:1px"))
    #expect(rule.contains("flex:0 0 1px"))
    #expect(rule.contains("align-self:stretch"), "as tall as the row")
    #expect(rule.contains("border-top-width:0") && rule.contains("border-left-width:1px"), "drawn along its leading edge")
  }

  /// A row that is proposed no height (a ScrollView's) is as tall as its other views and the Divider as tall as the row.
  @Test
  func aDividerInARowOfNoHeightStillStretches() {
    let rule = one(ScrollView { HStack { Text("Left"); Divider(); Text("Right") } }, tag: "hr")
    #expect(rule.contains("align-self:stretch"))
  }

  /// A frame, a padding or an overlay around it do not change the way it runs; a ZStack or a VStack do.
  @Test
  func aDividerRunsAlongTheStackAroundItsModifiers() {
    #expect(one(HStack { Text("L"); Divider().frame(height: 20); Text("R") }, tag: "hr").contains("border-left-width:1px"), "a frame")
    #expect(one(HStack { Text("L"); Divider().padding(.horizontal, 4); Text("R") }, tag: "hr").contains("border-left-width:1px"), "a padding")
    #expect(!one(HStack { Text("L"); ZStack { Divider() }; Text("R") }, tag: "hr").contains("border-left-width"), "a ZStack starts over")
    #expect(!one(HStack { Text("L"); VStack { Divider() }; Text("R") }, tag: "hr").contains("border-left-width"), "so does a VStack")
  }

  /// A Divider on its own (a frame's only view) is horizontal and as wide as the frame.
  @Test
  func aFramedDividerIsAsWideAsItsFrame() {
    let rule = one(VStack { Divider().frame(width: 100) }, tag: "hr")
    #expect(rule.contains("height:1px") && rule.contains("justify-self:stretch"))
  }

  /// A linear ProgressView takes the width of the stack and the track its view authored (the browser gives it neither).
  @Test
  func aProgressBarFillsTheWidthAndIsAsTallAsItsTrack() {
    let column = one(VStack(alignment: .leading) { ProgressView(value: 0.4) }.frame(width: 200), tag: "progress")
    #expect(column.contains("align-self:stretch") && column.contains("height:8px") && column.contains("flex:0 0 8px"))
    let row = one(HStack { Text("Loading"); ProgressView(value: 0.4) }.frame(width: 260), tag: "progress")
    #expect(row.contains("flex:1000000 1 0%"), "it takes what the row leaves")
    #expect(row.contains("height:8px"))
  }

  /// A spinner and a progress ring are 20 point squares (the stylesheet's 1.25rem), not the two borders of an empty span.
  @Test
  func aSpinnerAndARingAreTwentyPointSquares() {
    let spinner = one(HStack { ProgressView(); Text("Loading") }, tag: "span", className: "spinner-ring")
    #expect(spinner.contains("width:20px") && spinner.contains("height:20px"))
    let ring = one(HStack { ProgressView(value: 0.4).progressViewStyle(.circular); Text("Loading") }, tag: "span", className: "progress-ring")
    #expect(ring.contains("width:20px") && ring.contains("height:20px"))
  }

  /// A Slider takes the width of the stack (not the browser's 129 px) and the height of its track.
  @Test
  func aSliderFillsTheWidth() {
    let column = one(VStack(alignment: .leading) { Slider(value: .constant(0.4)) }.frame(width: 200), tag: "input")
    #expect(column.contains("align-self:stretch"))
    let row = one(HStack { Text("Volume"); Slider(value: .constant(0.4)); Text("100") }.frame(width: 320), tag: "input")
    #expect(row.contains("flex:1000000 1 0%"), "it takes what the row leaves")
  }

  /// A TextEditor takes the height of its frame, not its two rows.
  @Test
  func aTextEditorFillsItsFrame() {
    let rule = one(TextEditor(text: .constant("Notes")).frame(height: 90), tag: "textarea")
    #expect(rule.contains("height:100%") && rule.contains("align-self:stretch"))
    let column = one(VStack(alignment: .leading) { Text("Notes"); TextEditor(text: .constant("Notes")) }.frame(width: 200, height: 150), tag: "textarea")
    #expect(column.contains("flex:1000000 1 0%"), "it takes the height the stack leaves")
  }

  /// A view as tall as its content grows in a column up to that height, through the two variables Firefox sets to keep it
  /// at that height instead (it ignores `max-height: max-content`); a fixed height is written as it is.
  @Test
  func aViewHuggingItsHeightInAColumnSharesThroughTheFirefoxVariables() {
    let column = one(VStack { HStack { Text("Title"); Spacer() }.padding(); Color.blue }.frame(width: 200, height: 300), tag: "div", className: "padding")
    #expect(column.contains("flex:var(--sl-hug-grow,1000000) 1 var(--sl-hug-basis,0%)") && column.contains("max-height:max-content"))
    let fixed = one(VStack { HStack { Text("Title"); Spacer() }.padding().frame(height: 40); Color.blue }.frame(width: 200, height: 300), tag: "div", className: "padding")
    #expect(!fixed.contains("--sl-hug-grow"))
  }

  /// A Gauge's label is as wide as its text, its track as wide as the gauge.
  @Test
  func aGaugeKeepsItsLabelNarrow() {
    let rule = one(VStack { Gauge(value: 0.5, in: 0...1) { Text("Level") } }.frame(width: 200), tag: "div", className: "gauge-meter")
    #expect(rule.contains("align-items:flex-start"))
  }
}
