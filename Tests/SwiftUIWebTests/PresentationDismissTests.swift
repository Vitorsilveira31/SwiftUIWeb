import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber

private final class DismissCounter { var count = 0 }

private struct DismissItem: Identifiable, Equatable { let id: Int }

@Suite
@MainActor
struct PresentationDismissTests {
  private struct SheetFixture: View {
    @State var presented = true
    let counter: DismissCounter
    var isPresented: Bool { presented }
    func close() { presented = false }
    var body: some View {
      Text("Root")
        .sheet(isPresented: $presented, onDismiss: { counter.count += 1 }) {
          SheetBody()
        }
    }
  }

  private struct SheetBody: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Close") { dismiss() } }
  }

  @Test
  func onDismissRunsOnceWhenTheBindingIsReset() {
    let counter = DismissCounter()
    let fixture = SheetFixture(counter: counter)
    let tree = FiberTree(fixture)
    #expect(counter.count == 0)
    fixture.close()
    _ = tree.update(fixture)
    #expect(!fixture.isPresented)
    #expect(counter.count == 1)
    _ = tree.update(fixture)
    #expect(counter.count == 1)
  }

  @Test
  func onDismissRunsOnceForDismissActionAndForInteractiveDismissal() {
    let counter = DismissCounter()
    let fixture = SheetFixture(counter: counter)
    let tree = FiberTree(fixture)
    tree.dispatch(event: "click", on: tree.findNode(withEvent: "click"))
    _ = tree.update(fixture)
    #expect(!fixture.isPresented)
    #expect(counter.count == 1)

    let second = DismissCounter()
    let other = SheetFixture(counter: second)
    let otherTree = FiberTree(other)
    otherTree.dispatch(event: "presentation-dismiss", value: "escape")
    otherTree.dispatch(event: "presentation-dismiss")
    _ = otherTree.update(other)
    #expect(second.count == 1)
  }

  @Test
  func itemSheetDismissesWhenClearedAndWhenReplacedByAnotherItem() {
    struct Fixture: View {
      @State var item: DismissItem? = DismissItem(id: 1)
      let counter: DismissCounter
      func set(_ value: DismissItem?) { item = value }
      var body: some View {
        Text("Root").sheet(item: $item, onDismiss: { counter.count += 1 }) { item in Text("Item \(item.id)") }
      }
    }
    let counter = DismissCounter()
    let fixture = Fixture(counter: counter)
    let tree = FiberTree(fixture)
    fixture.set(DismissItem(id: 2))
    _ = tree.update(fixture)
    #expect(counter.count == 1)
    tree.dispatch(event: "presentation-dismiss")
    _ = tree.update(fixture)
    #expect(counter.count == 2)
    _ = tree.update(fixture)
    #expect(counter.count == 2)
  }

  @Test
  func alertPresentingRequiresDataAndPassesItToActionsAndMessage() {
    struct Fixture: View {
      @State var presented = true
      let data: String?
      var body: some View {
        Text("Root").alert("Delete?", isPresented: $presented, presenting: data) { name in
          Button("Delete \(name)", role: .destructive) {}
        } message: { name in
          Text("Remove \(name) permanently")
        }
      }
    }
    let shown = StaticHTMLFiberRenderer().render(Fixture(data: "Report"))
    #expect(shown.contains("Delete Report"))
    #expect(shown.contains("Remove Report permanently"))
    let hidden = StaticHTMLFiberRenderer().render(Fixture(data: nil))
    #expect(!hidden.contains("alert-panel"))
  }

  @Test
  func alertWithoutActionsGetsADefaultOKButtonAndTextTitlesWork() {
    struct Fixture: View {
      @State var presented = true
      var body: some View { Text("Root").alert(Text("Saved"), isPresented: $presented) {} }
    }
    let html = StaticHTMLFiberRenderer().render(Fixture())
    #expect(html.contains("aria-label=\"Saved\""))
    #expect(html.contains(">OK<"))
    #expect(html.contains("data-keyboard-shortcut=\"Enter|\""))
  }

  @Test
  func confirmationDialogTitleVisibilityAndPresenting() {
    struct Fixture: View {
      @State var presented = true
      let visibility: Visibility
      var body: some View {
        Text("Root").confirmationDialog("Choose", isPresented: $presented, titleVisibility: visibility, presenting: 3) { value in
          Button("Pick \(value)") {}
        }
      }
    }
    let automatic = StaticHTMLFiberRenderer().render(Fixture(visibility: .automatic))
    #expect(automatic.contains("aria-label=\"Choose\""))
    #expect(!automatic.contains("confirmation-dialog-title"))
    #expect(automatic.contains("Pick 3"))
    let visible = StaticHTMLFiberRenderer().render(Fixture(visibility: .visible))
    #expect(visible.contains("confirmation-dialog-title"))
  }
}
