import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// `NavigationStack(path: Binding<[Route]>)` and `List(_:selection:)` are the
/// everyday SwiftUI spellings for typed navigation and selectable lists.
@Suite
@MainActor
struct TypedPathAndListSelectionTests {
  enum Route: Hashable { case work(Int), settings }
  struct Work: Identifiable, Hashable { let id: Int; let title: String }

  final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
  }

  private struct Stack: View {
    let routes: Box<[Route]>
    var body: some View {
      NavigationStack(path: Binding(get: { routes.value }, set: { routes.value = $0 })) {
        VStack {
          Text("Root")
          NavigationLink(value: Route.work(2)) { Text("Open 2") }
        }
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .work(let id): Text("Work \(id)")
          case .settings: Text("Settings")
          }
        }
      }
    }
  }

  @Test
  func typedPathRendersItsDestinationsAndReceivesPushes() {
    let routes = Box<[Route]>([.settings])
    let tree = FiberTree(Stack(routes: routes), deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    #expect(Self.texts(in: tree.renderNode).contains("Settings"))

    routes.value = []
    _ = tree.update(Stack(routes: routes))
    guard let link = Self.fiber(in: tree.root, where: { Self.texts(in: $0.renderNode) == ["Open 2"] && $0.renderNode.events["click"] != nil }) else {
      Issue.record("NavigationLink was not rendered")
      return
    }
    tree.dispatch(event: "click", at: link.identity)
    #expect(routes.value == [.work(2)])
  }

  @Test
  func listSelectionReflectsAndWritesSingleAndMultipleSelection() {
    let works = [Work(id: 1, title: "A"), Work(id: 2, title: "B")]
    let single = Box<Int?>(2)
    let multiple = Box<Set<Int>>([])
    let view = VStack {
      List(works, selection: Binding(get: { single.value }, set: { single.value = $0 })) { Text($0.title) }
      List(works, selection: Binding(get: { multiple.value }, set: { multiple.value = $0 })) { Text("m" + $0.title) }
    }
    let tree = FiberTree(view, deferLazyCollections: false, startLifecycle: false)
    defer { tree._dispose() }
    let rows = Self.nodes(in: tree.renderNode) { $0.classes.contains("list-view-row-selectable") }
    #expect(rows.count == 4)
    #expect(rows.map { $0.attributes["aria-selected"] } == ["false", "true", "false", "false"])

    guard let rowA = Self.fiber(in: tree.root, where: { $0.renderNode.classes.contains("list-view-row-selectable") && Self.texts(in: $0.renderNode) == ["A"] }),
          let rowMB = Self.fiber(in: tree.root, where: { $0.renderNode.classes.contains("list-view-row-selectable") && Self.texts(in: $0.renderNode) == ["mB"] }) else {
      Issue.record("selectable rows were not rendered")
      return
    }
    tree.dispatch(event: "click", at: rowA.identity)
    tree.dispatch(event: "click", at: rowMB.identity)
    #expect(single.value == 1)
    #expect(multiple.value == [2])
  }

  private static func texts(in node: _RenderNode) -> [String] {
    if node.kind == .text, let text = node.text { return [text] }
    return node.children.flatMap(texts)
  }

  private static func nodes(in node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> [_RenderNode] {
    (predicate(node) ? [node] : []) + node.children.flatMap { nodes(in: $0, where: predicate) }
  }

  private static func fiber(in fiber: Fiber, where predicate: (Fiber) -> Bool) -> Fiber? {
    if predicate(fiber) { return fiber }
    for child in fiber.children {
      if let match = Self.fiber(in: child, where: predicate) { return match }
    }
    return nil
  }
}
