import Foundation
import Testing
@testable import SwiftUIWeb

@Suite
@MainActor
final class PresentationDetentsTests {
  @Test
  func testDetentsAreSerializedOnTheSheetPresentationSurface() {
    struct Fixture: View {
      @State private var presented = true
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          VStack { Text("Sheet content") }
            .presentationDetents([.height(280), .fraction(0.75), .medium, .large])
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(Fixture())
    _expectTrue(html.contains("class=\"presentation-root sheet-panel\""), html)
    _expectTrue(html.contains("data-presentation-detents=\"fraction(0.75),height(280.0),large,medium\""), html)
  }

  @Test
  func testSelectionBindingReceivesSnappedDetentValueEvent() {
    struct Fixture: View {
      @State private var presented = true
      @State private var selected = PresentationDetent.medium
      var selectedValue: PresentationDetent { selected }
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet")
            .presentationDetents([.medium, .large], selection: $selected)
        }
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    _expectNotNil(tree.findNode(withEvent: "presentation-detent"))
    tree.dispatch(event: "presentation-detent", value: "large")
    _expectEqual(fixture.selectedValue, .large)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-presentation-detent-selection=\"medium\""))
  }

  @Test
  func selectionBindingDecodesFractionAndHeightDetentsAndIgnoresMalformedValues() {
    struct Fixture: View {
      @State private var selected = PresentationDetent.medium
      var selectedValue: PresentationDetent { selected }
      var body: some View {
        Text("Sheet")
          .presentationDetents([.medium, .fraction(0.25), .height(320)], selection: $selected)
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    tree.dispatch(event: "presentation-detent", value: "fraction(0.25)")
    _expectEqual(fixture.selectedValue, .fraction(0.25))

    tree.dispatch(event: "presentation-detent", value: "height(320)")
    _expectEqual(fixture.selectedValue, .height(320))

    tree.dispatch(event: "presentation-detent", value: "fraction(not-a-number)")
    tree.dispatch(event: "presentation-detent", value: "unknown")
    _expectEqual(fixture.selectedValue, .height(320))
  }

  @Test
  func testProgrammaticSelectionIsReflectedAfterFiberRefresh() {
    struct Fixture: View {
      @State private var presented = true
      @State private var selected = PresentationDetent.medium
      mutating func setSelection(_ value: PresentationDetent) { selected = value }
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet")
            .presentationDetents([.medium, .large], selection: $selected)
        }
      }
    }

    var fixture = Fixture()
    let tree = FiberTree(fixture)
    fixture.setSelection(.large)
    _ = tree.update(fixture)
    _expectTrue(tree.renderNode.htmlDescription.contains("data-presentation-detent-selection=\"large\""))
  }

  @Test
  func testInteractiveDismissalStillUsesPresentationDismissEvent() {
    struct Fixture: View {
      @State private var presented = true
      var isPresented: Bool { presented }
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet")
            .presentationDetents([.medium, .large])
        }
      }
    }

    let fixture = Fixture()
    let tree = FiberTree(fixture)
    tree.dispatch(event: "presentation-dismiss")
    _expectFalse(fixture.isPresented)
  }

  @Test
  func testSheetPresentationMetadataPreservesDismissalAndDragIndicatorPolicy() {
    struct Fixture: View {
      @State private var presented = true
      var body: some View {
        Text("Root").sheet(isPresented: $presented) {
          Text("Sheet")
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled()
        }
      }
    }

    let html = StaticHTMLFiberRenderer().render(Fixture())
    _expectTrue(html.contains("data-presentation-drag-indicator=\"hidden\""), html)
    _expectTrue(html.contains("data-interactive-dismiss-disabled=\"true\""), html)
  }
}
