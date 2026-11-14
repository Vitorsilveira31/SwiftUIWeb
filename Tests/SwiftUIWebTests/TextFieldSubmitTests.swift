import Testing
@_spi(Renderer) import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

/// A text field takes Return itself only when it has `onCommit`; without one, Return reaches the `.onSubmit` of a view
/// around it, which the browser host finds as the nearest `submit` owner from the field up.
@Suite
@MainActor
struct TextFieldSubmitTests {
  private struct Field: View {
    @State var text = ""
    let log: Log
    var body: some View {
      VStack {
        TextField("Lock", text: $text)
      }
      .onSubmit { log.submits += 1 }
    }
  }

  final class Log { var submits = 0 }

  private func input(in node: _RenderNode) -> _RenderNode? {
    if case .element(let tag) = node.kind, tag == "input" { return node }
    for child in node.children { if let found = input(in: child) { return found } }
    return nil
  }

  private func submitOwner(in node: _RenderNode) -> _RenderNode? {
    if node.events["submit"] != nil { return node }
    for child in node.children { if let found = submitOwner(in: child) { return found } }
    return nil
  }

  /// Without `onCommit` the field has no submit handler of its own, so the `.onSubmit` around it owns Return.
  @Test
  func aFieldWithoutOnCommitLeavesReturnToTheOnSubmitAroundIt() throws {
    let log = Log()
    let tree = FiberTree(Field(log: log))
    let field = try #require(input(in: tree.renderNode))
    #expect(field.events["submit"] == nil)
    let owner = try #require(submitOwner(in: tree.renderNode))
    tree.dispatch(event: "submit", on: owner)
    #expect(log.submits == 1)
  }

  /// A field with `onCommit` still runs it on Return.
  @Test
  func aFieldWithOnCommitTakesReturnItself() throws {
    var commits = 0
    let tree = FiberTree(TextField("Name", text: .constant(""), onEditingChanged: { _ in }, onCommit: { commits += 1 }))
    let field = try #require(input(in: tree.renderNode))
    #expect(field.events["submit"] != nil)
    tree.dispatch(event: "submit", on: field)
    #expect(commits == 1)
  }
}
