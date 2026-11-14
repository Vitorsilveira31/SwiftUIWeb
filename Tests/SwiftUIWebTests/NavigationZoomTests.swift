import Foundation
import Testing
import SwiftUIWeb
@_spi(Renderer) @testable import SwiftUIWebCore
@_spi(Renderer) @testable import SwiftUIWebFeatures

/// `navigationTransition(.zoom(sourceID:in:))` takes the name of a source rendered earlier in the same stack: the name is on one
/// element at a time, and a push with no source, or with `.automatic`, names nothing new.
@Suite
@MainActor
struct NavigationZoomTests {
  /// A stack whose root holds two named sources, with the destination pushed when `pushed`.
  private struct Stack: View {
    @Namespace private var namespace
    @State private var path: NavigationPath
    let destinationTransition: (Namespace.ID) -> NavigationTransition

    init(pushed: Bool, destinationTransition: @escaping (Namespace.ID) -> NavigationTransition) {
      var initial = NavigationPath()
      if pushed { initial.append(1) }
      _path = State(initialValue: initial)
      self.destinationTransition = destinationTransition
    }

    var body: some View {
      let ns = namespace
      NavigationStack(path: $path) {
        VStack {
          Text("Card").matchedTransitionSource(id: "card", in: ns)
          Text("Other").matchedTransitionSource(id: "other", in: ns)
        }
        .navigationDestination(for: Int.self) { _ in
          Text("Zoomed").navigationTransition(destinationTransition(ns))
        }
      }
    }
  }

  /// The `view-transition-name` values of a rendered page, in order.
  private func names(_ html: String) -> [String] {
    html.components(separatedBy: "view-transition-name: ").dropFirst().map { part in
      String(part.prefix { $0 != ";" })
    }
  }

  @Test
  func zoomPushTakesTheSourceNameAndLeavesOneElementWithIt() {
    let html = StaticHTMLFiberRenderer().render(Stack(pushed: true) { .zoom(sourceID: "card", in: $0) })
    let found = names(html)
    #expect(found.count == 2, "the other source and the destination carry names, got \(found)")
    #expect(Set(found).count == found.count, "one name, one element: \(found)")
    #expect(html.contains("Zoomed"))
  }

  @Test
  func unpushedStackKeepsItsSourceNames() {
    let found = names(StaticHTMLFiberRenderer().render(Stack(pushed: false) { .zoom(sourceID: "card", in: $0) }))
    #expect(found.count == 2, "both sources are named before a push, got \(found)")
    #expect(Set(found).count == found.count)
  }

  @Test
  func zoomWithoutAMatchingSourceIsAPlainPush() {
    let found = names(StaticHTMLFiberRenderer().render(Stack(pushed: true) { .zoom(sourceID: "missing", in: $0) }))
    #expect(found.count == 2, "the sources keep their names and the destination has none, got \(found)")
    #expect(Set(found).count == found.count)
  }

  @Test
  func automaticIsAPlainPush() {
    let found = names(StaticHTMLFiberRenderer().render(Stack(pushed: true) { _ in .automatic }))
    #expect(found.count == 2, "automatic names nothing new, got \(found)")
    #expect(Set(found).count == found.count)
  }

  @Test
  func aZoomOfOneSourceLeavesTheOtherNamed() {
    let found = names(StaticHTMLFiberRenderer().render(Stack(pushed: true) { .zoom(sourceID: "other", in: $0) }))
    #expect(found.count == 2, "the card keeps its name and the destination takes the other's, got \(found)")
    #expect(Set(found).count == found.count)
  }

  /// A zoom inside an inner stack takes its name from the inner stack's own source, never from the outer one.
  private struct Nested: View {
    @Namespace private var namespace
    @State private var path: NavigationPath

    init() {
      var initial = NavigationPath()
      initial.append(1)
      _path = State(initialValue: initial)
    }

    var body: some View {
      let ns = namespace
      VStack {
        Text("Outer").matchedTransitionSource(id: "outer", in: ns)
        NavigationStack(path: $path) {
          Text("Inner").matchedTransitionSource(id: "inner", in: ns)
            .navigationDestination(for: Int.self) { _ in
              Text("Zoomed").navigationTransition(.zoom(sourceID: "inner", in: ns))
            }
        }
      }
    }
  }

  @Test
  func nestedStacksZoomFromTheirOwnSource() {
    let found = names(StaticHTMLFiberRenderer().render(Nested()))
    #expect(found.count == 2, "the outer source keeps its name and the inner destination takes the inner one, got \(found)")
    #expect(Set(found).count == found.count)
  }

  /// Keeps the render context a view renders under, so a test can register sources the way a destination that re-renders on
  /// its own does.
  private final class ContextCapture {
    var context: _RenderContext?
  }

  private struct ContextProbe: View {
    typealias Body = Never
    let capture: ContextCapture

    func _render(in context: _RenderContext) -> _RenderNode {
      capture.context = context
      return Text("Probe")._render(in: context)
    }
  }

  @Test
  func repeatedRegistrationKeepsOneNodePerNameAndZoomStillWorks() throws {
    let capture = ContextCapture()
    _ = StaticHTMLFiberRenderer().render(NavigationStack(path: .constant(NavigationPath())) { ContextProbe(capture: capture) })
    var context = try #require(capture.context)
    let navigation = try #require(context.navigationContext)
    let name = "vt-probe"

    // A destination that re-renders on its own registers its source again and again, without a stack render in between.
    var latest: _RenderNode?
    for _ in 0..<10 {
      let source = _RenderNode.element("span")
      ViewTransitionNameModifier(name: name)._apply(to: source, context: &context)
      latest = source
    }
    #expect(navigation.transitionSources[name] === latest, "the stack keeps only the latest source for the name")

    // The zoom still takes the name from that source, and the source gives it up.
    let destination = _RenderNode.element("span")
    NavigationTransitionModifier(transition: NavigationTransition(sourceName: name))._apply(to: destination, context: &context)
    #expect(latest?.styles["view-transition-name"] == nil, "the latest source gives its name up")
    #expect(destination.styles["view-transition-name"] == name, "the zoom destination carries the name")
  }
}
