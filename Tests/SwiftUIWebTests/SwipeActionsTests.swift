import Foundation
import Testing
import SwiftUIWebCore
import SwiftUIWebFeatures
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class SwipeActionsTests {
  @Test
  func testTrailingSwipeActionsRenderTheBuilderAndSemanticConfiguration() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Message")
        .swipeActions(allowsFullSwipe: false) {
          Button("Delete", role: .destructive, action: {})
          Button("Flag", action: {})
        }
    )

    _expectTrue(html.contains("data-swipe-actions=\"true\""))
    _expectTrue(html.contains("data-swipe-edge=\"trailing\""))
    _expectTrue(html.contains("data-swipe-full-swipe=\"false\""))
    _expectTrue(html.contains("swipe-actions-trailing"))
    _expectTrue(html.contains("Delete"))
    _expectTrue(html.contains("Flag"))
    _expectTrue(html.contains("data-role=\"destructive\""))
  }

  @Test
  func testLeadingActionsKeepLabelsTintAndMultipleButtons() {
    let html = StaticHTMLFiberRenderer().render(
      Text("Row")
        .swipeActions(edge: .leading) {
          Button("Archive", action: {}).tint(.blue)
          Button("More", role: .cancel, action: {})
        }
    )

    _expectTrue(html.contains("data-swipe-edge=\"leading\""))
    _expectTrue(html.contains("swipe-actions-leading"))
    _expectTrue(html.contains("data-tint=\"\(Color.blue.cssValue)\""))
    _expectTrue(html.contains("data-role=\"cancel\""))
    _expectEqual(html.components(separatedBy: "push-button").count - 1, 2)
    _expectEqual(html.components(separatedBy: "button-automatic").count - 1, 2)
  }

  @Test
  func testSwipeActionButtonsRemainFiberEventsAndIdentityIsStable() {
    struct Fixture: View {
      @State var title = "Row"
      var body: some View {
        List {
          Text(title)
            .id("row")
            .swipeActions {
              Button("Delete", role: .destructive) { title = "Deleted" }
            }
        }
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    let first = tree.renderNode.htmlDescription
    _expectTrue(first.contains("data-swipe-actions=\"true\""))
    _expectTrue(first.contains("data-role=\"destructive\""))

    // The action is represented by an ordinary button event. Dispatching it
    // changes state while the keyed row remains the same Fiber identity.
    tree.dispatch(event: "click")
    _ = tree.update(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("Deleted"))
    _expectTrue(tree.renderNode.htmlDescription.contains("data-swipe-actions=\"true\""))
  }

  @Test
  func testConditionalRowsReleaseSwipeActionSubtreeWithoutRebuildingSiblings() {
    struct Fixture: View {
      @State var showActions = true
      var body: some View {
        VStack {
          if showActions {
            Text("Visible").id("row").swipeActions {
              Button("Delete", role: .destructive, action: {})
            }
          } else {
            Text("Visible").id("row")
          }
          Text("Sibling").id("sibling")
        }
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-swipe-actions=\"true\""))
    fixture.showActions = false
    _ = tree.update(fixture)
    _expectFalse(tree.renderNode.htmlDescription.contains("data-swipe-actions=\"true\""))
    _expectTrue(tree.renderNode.htmlDescription.contains("Sibling"))
  }
}
