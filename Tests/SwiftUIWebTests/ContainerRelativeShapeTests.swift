import Testing
@testable @_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWeb

/// `ContainerRelativeShape` takes the shape of the nearest container that declares one (`containerShape`): Food Truck's
/// cards clip to it and take the corners of the Grid's 12-point rounded rectangle, as on iPad.
@Suite
@MainActor
struct ContainerRelativeShapeTests {
  @Test
  func aViewClippedToTheContainerShapeTakesTheContainersCornerRadius() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Text("Card").clipShape(ContainerRelativeShape())
      }
      .containerShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    )
    #expect(html.contains("--container-shape-radius: 12px"), "\(html)")
    #expect(html.contains("border-radius: var(--container-shape-radius, 0px)"), "\(html)")
  }

  @Test
  func withoutAContainerShapeItIsARectangle() {
    let html = StaticHTMLFiberRenderer().render(Text("Card").clipShape(ContainerRelativeShape()))
    // The fallback of the variable: no container hands a radius down.
    #expect(html.contains("var(--container-shape-radius, 0px)"), "\(html)")
    #expect(!html.contains("--container-shape-radius:"), "\(html)")
  }
}
