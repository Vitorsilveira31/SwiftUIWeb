import Foundation
import Testing
@testable import SwiftUIWeb
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
import SwiftUIWebHTML

private struct NestedStacks: View {
  let levels: Int
  var body: some View {
    if levels == 0 {
      Text("leaf").accessibilityIdentifier("leaf")
    } else {
      VStack(spacing: 0) { AnyView(NestedStacks(levels: levels - 1)) }
    }
  }
}

/// The deepest nesting of start and end tags in `html`, and the tags in the order they open.
private func nesting(of html: String) -> (maxDepth: Int, opened: [String]) {
  var depth = 0, maxDepth = 0
  var opened: [String] = []
  var index = html.startIndex
  while index < html.endIndex {
    guard html[index] == "<" else { index = html.index(after: index); continue }
    let closing = html[html.index(after: index)] == "/"
    var end = index
    while end < html.endIndex, html[end] != ">" { end = html.index(after: end) }
    if closing {
      depth -= 1
    } else {
      let name = html[html.index(after: index)...].prefix { $0 != " " && $0 != ">" }
      opened.append(String(name))
      depth += 1
      maxDepth = max(maxDepth, depth)
    }
    index = end < html.endIndex ? html.index(after: end) : end
  }
  return (maxDepth, opened)
}

@Suite
@MainActor
struct HTMLNestingDepthTests {
  @Test
  func theOutputStopsNestingAtTheLimitAndKeepsEveryElementInOrder() {
    let view = NestedStacks(levels: 40)
    let nested = StaticHTMLFiberRenderer().render(view)
    let flat = StaticHTMLFiberRenderer(maxElementDepth: 12).render(view)
    let before = nesting(of: nested), after = nesting(of: flat)
    #expect(before.maxDepth > 40)
    // The element opened at the limit is itself closed at once, so it is the one extra level.
    #expect(after.maxDepth == 13)
    #expect(after.opened == before.opened)
    #expect(flat.contains("id=\"leaf\"") || flat.contains("leaf"))
    // Balanced: every start tag is closed exactly once.
    #expect(flat.components(separatedBy: "</div>").count == nested.components(separatedBy: "</div>").count)
  }

  @Test
  func aTreeWithinTheLimitIsUnchanged() {
    let view = NestedStacks(levels: 5)
    let plain = StaticHTMLFiberRenderer().render(view)
    #expect(StaticHTMLFiberRenderer(maxElementDepth: 480).render(view) == plain)
    #expect(StaticHTMLFiberRenderer(maxElementDepth: 200).render(view) == StaticHTMLFiberRenderer().render(view))
  }
}
