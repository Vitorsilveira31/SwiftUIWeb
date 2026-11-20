import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A modifier on a `ForEach` changes each element where it stands, outside the owner that rendered the element (Food
/// Truck's New Orders tiles: `ForEach { tile }.aspectRatio(1, contentMode: .fit)`). A pass that renders one element's owner
/// again on its own returns the element without that wrapper: it has to be reconciled against the element, not against
/// the wrapper, or the element stands where the wrapper was and every layer below it is replaced (the tiles showed empty
/// while their new GeometryReaders waited to be measured).
@Suite(.serialized)
@MainActor
struct ElementModifierOwnerTests {
  private struct Item: Identifiable, Equatable {
    let id: Int
  }

  /// A tile with state of its own, the view a `ForEach` row is: a tap renders the row's owner again, and only it.
  private struct Tile: View {
    let id: Int
    @State private var taps = 0
    var body: some View {
      let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
      VStack {
        // A branch, so that the tap renders the owner again (a text alone is updated where it stands).
        if taps == 0 { Text("tile \(id)") } else { Text("tile \(id) taps \(taps)") }
        Button("tap \(id)") { taps += 1 }
      }
      .padding(6)
      .background(Color.gray, in: shape)
      .overlay { shape.strokeBorder(Color.secondary, lineWidth: 0.5) }
    }
  }

  /// A tile that is a stack and nothing else: the element the modifier wraps holds the stack's children, deferred when the
  /// render is staged.
  private struct BareTile: View {
    let id: Int
    @State private var taps = 0
    var body: some View {
      VStack {
        if taps == 0 { Text("tile \(id)") } else { Text("tile \(id) taps \(taps)") }
        Button("tap \(id)") { taps += 1 }
        ForEach(0..<12, id: \.self) { line in Text("line \(line)") }
      }
    }
  }

  private struct Tiles: View {
    let items = (0..<3).map { Item(id: $0) }
    let wrap: Wrap
    var bare = false
    var body: some View {
      VStack {
        switch wrap {
        case .aspectRatio:
          ForEach(items) { item in tile(item) }
            .aspectRatio(1, contentMode: .fit)
        case .frame:
          ForEach(items) { item in tile(item) }
            .frame(width: 80, height: 80)
        case .overlay:
          ForEach(items) { item in tile(item) }
            .overlay { Color.blue.opacity(0.1) }
        case .background:
          ForEach(items) { item in tile(item) }
            .background { Color.gray }
        case .padding:
          ForEach(items) { item in tile(item) }
            .padding(4)
        case .shapeBackground:
          ForEach(items) { item in tile(item) }
            .background(Color.gray, in: RoundedRectangle(cornerRadius: 4))
        }
      }
    }

    @ViewBuilder private func tile(_ item: Item) -> some View {
      if bare { BareTile(id: item.id) } else { Tile(id: item.id) }
    }
  }

  enum Wrap: CaseIterable {
    case aspectRatio, frame, padding, overlay, background, shapeBackground
  }

  private func texts(_ node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(texts)
  }

  private func button(_ fiber: Fiber, _ label: String) -> Fiber? {
    if fiber.renderNode.attributes["data-control-kind"] == "button", texts(fiber.renderNode) == [label] { return fiber }
    for child in fiber.children { if let found = button(child, label) { return found } }
    return nil
  }

  /// Every fiber of the tree, by identity, with the kind and the classes of its node.
  private func fibers(_ fiber: Fiber, into out: inout [ObjectIdentifier: String]) {
    out[ObjectIdentifier(fiber)] = fiber.renderNode.kind.displayName + "|" + fiber.renderNode.classes.joined(separator: ".")
    for child in fiber.children { fibers(child, into: &out) }
  }

  private func describe(_ node: _RenderNode, into out: inout [String], indent: Int = 0) {
    let pad = String(repeating: " ", count: indent)
    out.append("\(pad)\(node.kind.displayName)|\(node.classes)|\(node.text ?? "")")
    for child in node.children { describe(child, into: &out, indent: indent + 1) }
  }

  /// `content` under `depth` stacks: deep enough for the staged render to defer the rows, or their children.
  private struct Deep<Content: View>: View {
    let depth: Int
    let content: Content
    var body: some View {
      if depth == 0 { content } else { VStack { Deep(depth: depth - 1, content: content) } }
    }
  }

  @Test(arguments: Wrap.allCases)
  func renderingAnElementOwnerAgainKeepsTheFibersOfTheWrappedElement(wrap: Wrap) {
    check(wrap, budget: 0, depth: 0)
  }

  /// The same with the render staged (`_RenderStaging`, as in Embedded Swift): a row whose children are deferred when the
  /// modifier wraps it, and children the modifier makes render while it reads the row.
  @Test(arguments: Wrap.allCases)
  func aStagedRowKeepsItsFibersToo(wrap: Wrap) {
    for budget in [1, 2, 3, 4, 6, 8, 12] {
      for depth in [0, 4, 10] {
        check(wrap, budget: budget, depth: depth)
        check(wrap, budget: budget, depth: depth, bare: true)
      }
    }
  }

  private func check(_ wrap: Wrap, budget: Int, depth: Int, bare: Bool = false) {
    let saved = _RenderStaging.budget
    _RenderStaging.budget = budget
    defer { _RenderStaging.budget = saved }
    let tree = FiberTree(Deep(depth: depth, content: Tiles(wrap: wrap, bare: bare)), deferLazyCollections: false)
    defer { tree._dispose() }
    _ = tree.renderNode
    var before: [ObjectIdentifier: String] = [:]
    fibers(tree.root, into: &before)
    guard let tap = button(tree.root, "tap 1") else { Issue.record("missing the button"); return }
    tree.dispatch(event: "click", at: tap.identity)
    _ = tree.renderNode
    var after: [ObjectIdentifier: String] = [:]
    fibers(tree.root, into: &after)
    #expect(texts(tree.renderNode).contains("tile 1 taps 1"))
    // The tap took the other branch of the tile's text: that text is the one new fiber of the page.
    let added = after.filter { before[$0.key] == nil }.map(\.value).sorted()
    #expect(added == ["text|"], "\(wrap), budget \(budget), depth \(depth), bare \(bare): new fibers \(added)")
    // And the page is what a render from scratch of the same state draws.
    var rendered: [String] = []
    describe(tree.renderNode, into: &rendered)
    #expect(rendered.contains { $0.contains("tile 1 taps 1") })
    #expect(rendered.filter { $0.contains("aspect-box") || $0.contains("frame-box") }.count == (wrap == .aspectRatio || wrap == .frame ? 3 : 0),
            "\(wrap), budget \(budget), depth \(depth), bare \(bare): the element wrappers are not all there")
  }
}
