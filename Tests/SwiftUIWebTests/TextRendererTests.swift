import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// `TextRenderer`: the layout the page reports for a text, the runs and attributes a renderer reads from it, and the
/// canvas its drawing becomes.
@MainActor
struct TextRendererTests {
  // The ellipsis the page draws where it cuts a text is drawn with the layout but is not one of the text's characters.
  @Test
  func theEllipsisOfACutTextIsNotPartOfTheTextToLayOutAgain() throws {
    let cut = [
      "0,0,100,20,1",
      "L\u{1F}0,16,30,13,4,2",
      "R\u{1F}0,0,0,16,30,13,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)",
      "G\u{1F}0,10,0\u{1F}a",
      "G\u{1F}10,10,1\u{1F}b",
      "G\u{1F}20,10,2,1\u{1F}\u{2026}",
      "H\u{1F}20,10,2\u{1F}c",
    ].joined(separator: "\u{1E}")
    let measured = try #require(_MeasuredTextLayout(decoding: cut))
    #expect(measured.lines[0].runs[0].glyphs.count == 3)
    #expect(measured.lines[0].runs[0].glyphs[2].synthetic)
    // a, b and the hidden c: three characters, not four.
    #expect(measured.flow?.pieces.count == 3)
    // It is still drawn.
    #expect(measured.layout(attributes: [])[0].flatMap { $0 }.count == 3)
  }

  // A line too narrow for a glyph beside the ellipsis is the ellipsis alone: it stands for the line's first character, so a
  // newline after it is not taken for one before the first line.
  @Test
  func aLineThatIsOnlyTheEllipsisKeepsItsPlace() throws {
    let cut = [
      "0,0,16,20,1",
      "L\u{1F}0,16,12,13,4,2",
      "R\u{1F}0,0,0,16,12,13,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)",
      "G\u{1F}0,12,0,1\u{1F}\u{2026}",
      "S\u{1F}1,0,1",
      "H\u{1F}0,12,0\u{1F}W",
      "H\u{1F}0,12,2\u{1F}b",
    ].joined(separator: "\u{1E}")
    let measured = try #require(_MeasuredTextLayout(decoding: cut))
    #expect(measured.lines[0].runs[0].glyphs.count == 1)
    // The first line's baseline, descent and half leading: no line advance is taken off for the newline that follows it.
    #expect(measured.flow?.firstLine == 21)
  }

  @Test
  func theMeasuredLayoutHasLinesRunsAndGlyphs() throws {
    let measured = try #require(_MeasuredTextLayout(decoding: twoRuns))
    let layout = measured.layout(attributes: [])
    #expect(layout.count == 1)
    #expect(!layout.isTruncated)
    let line = layout[0]
    #expect(line.count == 2)
    #expect(line.origin == CGPoint(x: 0, y: 16))
    #expect(line.typographicBounds.width == 30)
    #expect(line.typographicBounds.rect == CGRect(x: 0, y: 3, width: 30, height: 17))
    let first = line[0]
    #expect(first.count == 2)
    #expect(first.characterIndices.map { first.characterIndices[0].distance(to: $0) } == [0, 1])
    #expect(first[1].typographicBounds.origin == CGPoint(x: 10, y: 16))
    #expect(first[1].typographicBounds.width == 10)
    #expect(first[0..<2].typographicBounds.width == 20)
    #expect(line[1].layoutDirection == .leftToRight)
    #expect(line[1].typographicBounds.origin.x == 20)
  }

  @Test
  func aTextIsMeasuredThenDrawnWithItsRunsAttributes() throws {
    let tree = FiberTree(Highlighted())
    defer { tree._dispose() }
    // Until the page reports the layout, the text shows as it does by itself.
    let before = tree.renderNode.htmlDescription
    #expect(before.contains("data-text-layout=\"true\""))
    #expect(before.contains("data-text-run=\"0\"") && before.contains("data-text-run=\"1\""))
    #expect(_canvas(in: tree.renderNode) == nil)

    tree.dispatch(event: "textLayout", value: twoRuns)
    let canvas = try #require(_canvas(in: tree.renderNode))
    // Only the run that carries the attribute is drawn, from its baseline origin, with its own font and color.
    let glyphs = canvas._canvasCommands.compactMap { command -> String? in
      if case .glyphs(let text, let x, let y, let font, let color, _, _, _) = command { return "\(text)@\(Int(x)),\(Int(y)) \(font) \(color)" }
      return nil
    }
    #expect(glyphs == ["ab@0,16 13px sans-serif rgb(0, 0, 0)"])
    #expect(canvas.attributes["data-canvas-size"] == "100,40")
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("-webkit-text-fill-color: transparent"))
  }

  @Test
  func displayPaddingGrowsTheCanvasAndSizeThatFitsSizesTheText() throws {
    let tree = FiberTree(Padded())
    defer { tree._dispose() }
    tree.dispatch(event: "textLayout", value: twoRuns)
    let canvas = try #require(_canvas(in: tree.renderNode))
    #expect(canvas.attributes["data-canvas-size"] == "110,40")
    #expect(canvas.styles["left"] == "-4px")
    let translations = canvas._canvasCommands.compactMap { command -> Double? in
      if case .translate(let x, _) = command { return x }
      return nil
    }
    #expect(translations.first == 4)
    // The renderer makes the text 20 points wider than it is.
    #expect(tree.renderNode.htmlDescription.contains("width: 50px"))
  }

  @Test
  func textProxyWrapsANarrowerProposal() {
    let proxy = TextProxy(_size: CGSize(width: 100, height: 20), _lineCount: 1)
    #expect(proxy.sizeThatFits(.unspecified) == CGSize(width: 100, height: 20))
    #expect(proxy.sizeThatFits(ProposedViewSize(width: 40, height: nil)) == CGSize(width: 40, height: 60))
  }
}

/// One line: "ab" in the first run, "c" bold in the second.
let twoRuns = [
  "0,0,100,40,0",
  "L\u{1F}0,16,30,13,4,2",
  "R\u{1F}0,0,0,16,20,13,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)",
  "G\u{1F}0,10,0\u{1F}a",
  "G\u{1F}10,10,1\u{1F}b",
  "R\u{1F}1,0,20,16,10,13,4,0\u{1F}700 13px sans-serif\u{1F}rgb(255, 0, 0)",
  "G\u{1F}20,10,2\u{1F}c",
].joined(separator: "\u{1E}")

@MainActor func _canvas(in node: _RenderNode) -> _RenderNode? {
  if node.attributes["data-text-renderer-canvas"] == "true" { return node }
  for child in node.children { if let found = _canvas(in: child) { return found } }
  return nil
}

private struct Tag: TextAttribute { var id: Int }

nonisolated private struct Highlight: TextRenderer {
  func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    for line in layout {
      for run in line where run[Tag.self] != nil { ctx.draw(run) }
    }
  }
}

private struct Highlighted: View {
  var body: some View {
    (Text("ab").customAttribute(Tag(id: 1)) + Text("c").bold()).textRenderer(Highlight())
  }
}

nonisolated private struct Wide: TextRenderer {
  var displayPadding: EdgeInsets { EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 6) }
  func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
    let size = text.sizeThatFits(proposal)
    return CGSize(width: size.width + 20, height: size.height)
  }
  func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    for line in layout { ctx.draw(line) }
  }
}

private struct Padded: View {
  var body: some View { Text("abc").textRenderer(Wide()) }
}

/// What a run carries beyond its glyphs: an underline, a gradient, and the white space the page laid out without a box.
@MainActor
struct TextRendererStyleTests {
  @Test
  func anUnderlinedRunDrawsItsLineAndAGradientRunItsShading() throws {
    let tree = FiberTree(Whole())
    defer { tree._dispose() }
    tree.dispatch(event: "textLayout", value: styledRun)
    let canvas = try #require(_canvas(in: tree.renderNode))
    let decorations = canvas._canvasCommands.compactMap { command -> String? in
      if case .textDecoration(let x0, let x1, let y, let thickness, let color) = command { return "\(Int(x0))-\(Int(x1))@\(Int(y)) \(Int(thickness)) \(color)" }
      return nil
    }
    #expect(decorations == ["0-20@18 1 rgb(255, 0, 0)"])
    let paints = canvas._canvasCommands.compactMap { command -> String? in
      if case .glyphs(_, _, _, _, _, _, _, let paint) = command { return paint }
      return nil
    }
    #expect(paints == [gradient])
    #expect(canvas.attributes["data-canvas-commands"]?.contains("\"p\":" + gradient) == true)
  }

  @Test
  func aRendererKeepsTheDecorationColorAndGradientForThePage() throws {
    let tree = FiberTree(Painted())
    defer { tree._dispose() }
    tree.dispatch(event: "textLayout", value: twoRuns)
    let html = tree.renderNode.htmlDescription
    #expect(html.contains("data-text-paint-decoration=\"light-dark("))
    #expect(html.contains("data-text-paint-image=\"linear-gradient("))
    #expect(html.contains("background-image: none"))
  }

  @Test
  func aTextUnderAContainersGradientHidesItsGlyphsAndTheDrawingReadsIt() throws {
    let tree = FiberTree(UnderGradient())
    defer { tree._dispose() }
    tree.dispatch(event: "textLayout", value: twoRuns)
    let canvas = try #require(_canvas(in: tree.renderNode))
    #expect(canvas.styles["visibility"] == "visible")
    #expect(canvas.attributes["role"] == "img")
    #expect(canvas.attributes["aria-label"] == "abc")
    #expect(canvas.attributes["aria-hidden"] == nil)
    #expect(tree.renderNode.htmlDescription.contains("visibility: hidden"))
  }

  @Test
  func aTextWithoutAPaintAboveKeepsItsGlyphsForSelection() throws {
    let tree = FiberTree(Painted())
    defer { tree._dispose() }
    tree.dispatch(event: "textLayout", value: twoRuns)
    let canvas = try #require(_canvas(in: tree.renderNode))
    #expect(canvas.attributes["aria-hidden"] == "true")
    #expect(!tree.renderNode.htmlDescription.contains("visibility"))
  }

  @Test
  func textProxyLaysTheTextOutAgainAtAnotherWidth() throws {
    let measured = try #require(_MeasuredTextLayout(decoding: words))
    let flow = try #require(measured.flow)
    // "ab cd": 10 points a letter, 5 the space the page drew no box for.
    #expect(flow.size(fitting: nil) == CGSize(width: 45, height: 20))
    #expect(flow.size(fitting: 30) == CGSize(width: 20, height: 40))
    // A word longer than the width breaks where it runs out.
    #expect(flow.size(fitting: 15) == CGSize(width: 10, height: 80))
    let proxy = TextProxy(_size: measured.contentSize, _lineCount: measured.lines.count, _flow: flow)
    #expect(proxy.sizeThatFits(ProposedViewSize(width: 100, height: nil)) == CGSize(width: 45, height: 20))
  }

  // A blank line between two lines with glyphs is an advance the page reports no line for: it is not folded into one.
  @Test
  func aBlankInteriorLineIsALineAdvanceOfItsOwn() throws {
    // "a\n\nb" with 20 point lines: a and b on baselines 14 and 54, a newline for each of the two breaks.
    let measured = try #require(_MeasuredTextLayout(decoding: [
      "0,0,10,60,0",
      "L\u{1F}0,14,10,12,4,4",
      "R\u{1F}0,0,0,14,10,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
      "G\u{1F}0,10,0\u{1F}a",
      "L\u{1F}0,54,10,12,4,4",
      "R\u{1F}0,0,0,54,10,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
      "G\u{1F}0,10,3\u{1F}b",
      "S\u{1F}1,0,1",
      "S\u{1F}2,0,1",
    ].joined(separator: "\u{1E}")))
    let flow = try #require(measured.flow)
    #expect(flow.lineHeight == 20)
    #expect(flow.size(fitting: nil) == CGSize(width: 10, height: 60))
    // Without the blank line, the second line is one advance below the first.
    let plain = try #require(_MeasuredTextLayout(decoding: [
      "0,0,10,40,0",
      "L\u{1F}0,14,10,12,4,4",
      "R\u{1F}0,0,0,14,10,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
      "G\u{1F}0,10,0\u{1F}a",
      "L\u{1F}0,34,10,12,4,4",
      "R\u{1F}0,0,0,34,10,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
      "G\u{1F}0,10,2\u{1F}b",
      "S\u{1F}1,0,1",
    ].joined(separator: "\u{1E}")))
    #expect(plain.flow?.lineHeight == 20)
  }

  // A text that begins with a newline: its first reported line is below the blank one, which the reflow must not count twice.
  @Test
  func aLeadingNewlineIsCountedOnceByTheReflow() throws {
    // "\na" with 20 point lines: a on baseline 34, the newline a gap before it.
    let measured = try #require(_MeasuredTextLayout(decoding: [
      "0,0,10,40,0",
      "L\u{1F}0,34,10,12,4,4",
      "R\u{1F}0,0,0,34,10,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
      "G\u{1F}0,10,1\u{1F}a",
      "S\u{1F}0,0,1",
    ].joined(separator: "\u{1E}")))
    let flow = try #require(measured.flow)
    #expect(flow.size(fitting: nil) == CGSize(width: 10, height: 40))
  }

  @Test
  func aTruncatedTextLaysOutWithItsHiddenLinesUpToItsLimit() throws {
    // "ab cd" at 20 points: "cd" is on a second line that a limit of one line hides.
    let measured = try #require(_MeasuredTextLayout(decoding: [
      "0,0,20,20,1",
      "L\u{1F}0,14,20,12,4,4",
      "R\u{1F}0,0,0,14,20,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
      "G\u{1F}0,10,0\u{1F}a",
      "G\u{1F}10,10,1\u{1F}b",
      "S\u{1F}2,5,0",
      "H\u{1F}0,10,3\u{1F}c",
      "H\u{1F}10,10,4\u{1F}d",
    ].joined(separator: "\u{1E}")))
    #expect(measured.truncated)
    #expect(measured.layout(attributes: []).count == 1)
    let flow = try #require(measured.flow)
    #expect(flow.size(fitting: nil) == CGSize(width: 45, height: 20))
    #expect(flow.size(fitting: 30, lineLimit: 1) == CGSize(width: 30, height: 20))
    #expect(flow.size(fitting: 30, lineLimit: 2) == CGSize(width: 20, height: 40))
  }
}

let gradient = "{\"k\":\"l\",\"x0\":0,\"y0\":0,\"x1\":20,\"y1\":0,\"s\":[[\"red\",0],[\"blue\",1]]}"

/// One run of "ab", underlined in red, painted with a gradient.
let styledRun = [
  "0,0,100,40,0",
  "L\u{1F}0,16,20,13,4,2",
  "R\u{1F}0,0,0,16,20,13,4,0\u{1F}13px sans-serif\u{1F}rgba(0, 0, 0, 0)\u{1F}underline|rgb(255, 0, 0)|1|2|-4\u{1F}" + gradient,
  "G\u{1F}0,10,0\u{1F}a",
  "G\u{1F}10,10,1\u{1F}b",
].joined(separator: "\u{1E}")

/// "ab cd" on one line 20 points high, the space without a box.
let words = [
  "0,0,45,20,0",
  "L\u{1F}0,14,45,12,4,4",
  "R\u{1F}0,0,0,14,45,12,4,0\u{1F}13px sans-serif\u{1F}rgb(0, 0, 0)\u{1F}\u{1F}",
  "G\u{1F}0,10,0\u{1F}a",
  "G\u{1F}10,10,1\u{1F}b",
  "G\u{1F}25,10,3\u{1F}c",
  "G\u{1F}35,10,4\u{1F}d",
  "S\u{1F}2,5,0",
].joined(separator: "\u{1E}")

nonisolated private struct Everything: TextRenderer {
  func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    for line in layout { ctx.draw(line) }
  }
}

private struct Whole: View {
  var body: some View { Text("ab").textRenderer(Everything()) }
}

private struct UnderGradient: View {
  var body: some View {
    VStack {
      (Text("ab") + Text("c").bold()).textRenderer(Everything())
    }
    .foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
  }
}

private struct Painted: View {
  var body: some View {
    (Text("ab").underline(color: .red) + Text("c").foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)))
      .textRenderer(Everything())
  }
}
