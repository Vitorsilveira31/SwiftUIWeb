import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Browser) @_spi(Renderer) @testable import SwiftUIWebBrowser

extension _CSSLayoutEmitter {
  /// The rules `rulesAttribute` writes, with the lengths each element carries (`--len<i>`) put back where its rule reads them:
  /// one line for each distinct set of lengths, so a test reads the pixels a block lays an element out with.
  func resolvedRules() -> String {
    let lines = (rulesAttribute(acked: 0) ?? "").split(separator: "\n").map(String.init)
    var lengthsByRule: [Int: Set<[String]>] = [:]
    for (key, id) in assigned { lengthsByRule[id, default: []].insert(assignedLengths[key] ?? []) }
    var out: [String] = []
    for line in lines {
      guard line.hasPrefix(".sl"), let brace = line.firstIndex(of: "{"), let id = Int(line[line.index(line.startIndex, offsetBy: 3)..<brace]), let sets = lengthsByRule[id] else { out.append(line); continue }
      for lengths in sets.sorted(by: { $0.joined(separator: ",") < $1.joined(separator: ",") }) {
        var resolved = line
        // Highest index first: `--len1` is not part of `--len10`.
        for (index, length) in lengths.enumerated().reversed() { resolved = resolved.replacingOccurrences(of: "var(--len\(index))", with: length) }
        out.append(resolved)
      }
    }
    return out.joined(separator: "\n")
  }
}

@MainActor
struct CSSLayoutEmitterLengthTests {
  /// The emitter after one run over `content`, and the tree it styled (disposed by the caller).
  private func styled<V: View>(_ content: V) -> (emitter: _CSSLayoutEmitter, tree: FiberTree) {
    let tree = FiberTree(content, deferLazyCollections: false)
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    return (emitter, tree)
  }

  /// The rules and the lengths of the elements for a frame of `width` (a Board's column following the window).
  private func frameRules(maxWidth width: Double) -> (rules: [String], lengths: [[String]]) {
    let (emitter, tree) = styled(Text("Board").frame(maxWidth: width).frame(maxWidth: .infinity))
    defer { tree._dispose() }
    let rules = (emitter.rulesAttribute(acked: 0) ?? "").split(separator: "\n").map(String.init)
    return (rules, emitter.assignedLengths.values.sorted { $0.joined(separator: ",") < $1.joined(separator: ",") })
  }

  /// A frame's size that follows the window is an inline length of the element: the rule is the same for every value, so a
  /// resize step adds no rule to the page's stylesheet.
  @Test
  func aFramesMaximumIsALengthOfTheElementNotOfItsRule() {
    let wide = frameRules(maxWidth: 971), narrow = frameRules(maxWidth: 961)
    #expect(!wide.rules.isEmpty)
    #expect(wide.rules == narrow.rules, "the rules do not depend on the value")
    #expect(wide.rules.contains { $0.contains("var(--len") && !$0.contains("971px") }, "the rule reads a variable")
    #expect(wide.lengths.contains { $0.contains("971px") } && narrow.lengths.contains { $0.contains("961px") } && !narrow.lengths.contains { $0.contains("971px") })
  }

  /// The same emitter, a new value: the block ids stay, the elements' lengths change, and the rules the host has not got yet are none.
  @Test
  func aNewValueRewritesTheLengthsAndMintsNoRule() {
    func board(_ width: Double) -> some View { Text("Board").frame(maxWidth: width).frame(maxWidth: .infinity) }
    let tree = FiberTree(board(971), deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.run(tree.root)
    emitter.published(epoch: 1)
    let blocks = emitter.assigned.values.sorted()
    let lengths = emitter.assignedLengths.values.flatMap { $0 }
    #expect(lengths.contains("971px"))
    _ = tree._advanceEpoch()
    _ = tree.update(board(961))
    emitter.run(tree.root)
    #expect(emitter.rulesAttribute(acked: 1) == nil, "no new rule for the new value")
    #expect(emitter.assigned.values.sorted() == blocks, "the same blocks")
    let after = emitter.assignedLengths.values.flatMap { $0 }
    #expect(after.contains("961px") && !after.contains("971px"), "other lengths")
    #expect(!emitter.changed.isEmpty, "the element is published again")
  }

  /// Lengths that are not a frame's or a position's stay in the rule: only what follows a resize, a scroll or an animation is
  /// a variable.
  @Test
  func paddingsAndGapsStayInTheRule() {
    let (emitter, tree) = styled(VStack(spacing: 12) { Text("A").padding(7); Text("B") }.frame(maxWidth: .infinity))
    defer { tree._dispose() }
    let rules = emitter.rulesAttribute(acked: 0) ?? ""
    #expect(rules.contains("gap:12px") && rules.contains("padding:7px 7px 7px 7px"))
  }

  /// A collapsed rail's block keeps its lengths in the text: an element carries one set of `--len<i>`, its expanded block's.
  @Test
  func lengthVariablesTakeTheMarkedLengthsInOrder() {
    let marked = "width:" + _cssVpx(971) + "!important;min-width:" + _cssVpx(0) + "!important;gap:8px!important"
    let (text, lengths) = _cssLengthVariables(marked)
    #expect(text == "width:var(--len0)!important;min-width:var(--len1)!important;gap:8px!important")
    #expect(lengths == ["971px", "0px"])
    let (literal, none) = _cssLengthVariables(marked, variables: false)
    #expect(literal == "width:971px!important;min-width:0px!important;gap:8px!important")
    #expect(none.isEmpty)
  }

  /// The page keeps every rule it was sent: past a limit of blocks the emitter stops, and the page's mapper lays the roots out.
  @Test
  func stopsStylingPastTheBlockLimit() {
    let tree = FiberTree(VStack { Text("A"); Text("B").frame(width: 40) }.frame(maxWidth: .infinity), deferLazyCollections: false)
    defer { tree._dispose() }
    let emitter = _CSSLayoutEmitter()
    emitter.enabled = true
    emitter.blockLimit = 3
    emitter.run(tree.root)
    #expect(!emitter.assigned.isEmpty && !emitter.roots.isEmpty, "styled while under the limit")
    emitter.run(tree.root)
    #expect(emitter.assigned.isEmpty && emitter.assignedLengths.isEmpty && emitter.roots.isEmpty, "released over it")
    #expect(emitter.forceFull, "the page's mapper takes the root over")
  }
}
