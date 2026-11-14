import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Browser) @_spi(Renderer) @testable import SwiftUIWebBrowser

/// Nested stacks, one level per view, as deep as asked.
private struct DeepStack: View {
  let depth: Int
  var body: some View {
    if depth == 0 {
      Text("leaf")
    } else {
      VStack(spacing: 0) { AnyView(DeepStack(depth: depth - 1)) }.padding(1)
    }
  }
}

@MainActor
struct CSSLayoutEmitterDepthTests {
  /// How far down the call stack the emitter goes for a tree `depth` levels deep, in bytes.
  private func stackBytes(depth: Int) -> (bytes: UInt, analysed: Int) {
    let tree = FiberTree(DeepStack(depth: depth), deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    var marker = 0
    let base = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
    var lowest = base
    _CSSLayoutEmitter.stackProbe = {
      var marker = 0
      lowest = min(lowest, withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) })
    }
    defer { _CSSLayoutEmitter.stackProbe = nil }
    emitter.run(tree.root)
    return (base - lowest, emitter.analysedCount)
  }

  /// A sidebar slot's content is a root of its own, styled for the expanded sidebar and for the collapsed rail: in the
  /// rail the bottom bar's `.hstack` keeps only its first child (the stylesheet's `.hstack > :not(:first-child)`).
  @Test
  func stylesASidebarSlotForTheExpandedSidebarAndTheRail() {
    let tree = FiberTree(
      TabView {
        Tab("Home", systemImage: "house") { Text("Home") }
        Tab("Works", systemImage: "book") { Text("Works") }
      }
      .tabViewStyle(.sidebarAdaptable)
      .tabViewSidebarBottomBar { HStack { Text("AB"); Text("Signed-in user") } },
      deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    func elements(_ fiber: Fiber) -> [Fiber] {
      var out: [Fiber] = [], stack = [fiber]
      while let f = stack.popLast() { out.append(f); stack.append(contentsOf: f.children.reversed()) }
      return out
    }
    let all = elements(tree.root)
    guard let stack = all.first(where: { $0.renderNode.classes.contains("hstack") && $0.renderNode.attributes["data-layout-kind"] == "hstack" }) else {
      Issue.record("no HStack in the bottom bar"); return
    }
    let texts = elements(stack).filter { $0 !== stack && emitter.assigned[ObjectIdentifier($0)] != nil }
    #expect(emitter.roots.contains(ObjectIdentifier(stack)), "the slot's content is a root CSS lays out")
    #expect(texts.count == 2)
    guard texts.count == 2 else { return }
    guard let hidden = emitter.railAssigned[ObjectIdentifier(texts[1])], let first = emitter.railAssigned[ObjectIdentifier(texts[0])] else {
      Issue.record("the rail styles both children"); return
    }
    let rules = emitter.resolvedRules()
    #expect(rules.contains(".sr\(hidden){display:none!important}"), "the rail hides the second child")
    #expect(!rules.contains(".sr\(first){display:none!important}"), "and keeps the first")
  }

  /// A frame with a minimum and no maximum around a fixed frame, inside a padding (a tab bar's icon): one element whose
  /// track is the fixed frame, kept at least the minimum wide and aligned at its leading edge.
  @Test
  func foldsAMinimumFrameAroundAFixedFrame() {
    let tree = FiberTree(
      HStack {
        Text("A").frame(width: 24, height: 24).frame(minWidth: 54, alignment: .leading).padding(.vertical, 6)
        Text("label")
      },
      deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    var chain: Fiber?, stack = [tree.root]
    while let f = stack.popLast() {
      if f.renderNode.attributes["data-layout-wrap"]?.contains("frame-min-w=54") == true { chain = f; break }
      stack.append(contentsOf: f.children)
    }
    guard let chain else { Issue.record("no merged chain"); return }
    guard let id = emitter.assigned[ObjectIdentifier(chain)] else { Issue.record("the chain is not styled"); return }
    let rules = emitter.resolvedRules()
    guard let line = rules.split(separator: "\n").first(where: { $0.hasPrefix(".sl\(id){") }) else { Issue.record("no rule for the chain"); return }
    #expect(line.contains("grid-template-columns:24px"), "the fixed frame is the track")
    #expect(line.contains("min-width:54px"), "the minimum keeps the element at least that wide")
    #expect(line.contains("justify-content:start"), "and aligns the track at the leading edge")
  }

  /// The emitter walks the tree with stacks of its own, so the call stack it needs does not grow with the tree's depth:
  /// one call per level overflowed a Worker's call stack in a large app, and the runtime then ran the app on the
  /// main thread for the rest of the session.
  @Test
  func aDeeperTreeTakesNoMoreCallStack() {
    let shallow = stackBytes(depth: 40), deep = stackBytes(depth: 160)
    print("METRIC css emitter stack: \(shallow.bytes) bytes at 40 levels, \(deep.bytes) at 160")
    #expect(deep.analysed >= 160 && shallow.analysed >= 40)
    #expect(deep.bytes <= shallow.bytes + 1024, "stack \(deep.bytes) bytes at 160 levels vs \(shallow.bytes) at 40")
  }
}
