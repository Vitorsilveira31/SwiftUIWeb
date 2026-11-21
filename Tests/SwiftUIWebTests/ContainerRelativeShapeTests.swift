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

  @Test
  func aBackgroundWithoutAShapeTakesTheContainersCornersOnlyUnderAContainerShape() {
    let inside = StaticHTMLFiberRenderer().render(
      VStack { Text("Card").background() }.containerShape(RoundedRectangle(cornerRadius: 12))
    )
    #expect(inside.contains("border-radius: 12px"), "\(inside)")
    // Elsewhere a component keeps the corners its stylesheet gives it (a button with a clear background).
    let outside = StaticHTMLFiberRenderer().render(Button("Save") {}.background(.clear))
    #expect(!outside.contains("border-radius: var(--container-shape-radius"), "\(outside)")
    #expect(!outside.contains("border-radius: 0px"), "\(outside)")
  }

  @Test
  func aContainerRelativeShapeDrawnOnItsOwnIsRoundedByTheContainer() {
    let html = StaticHTMLFiberRenderer().render(
      ZStack { ContainerRelativeShape().fill(Color.blue) }.containerShape(RoundedRectangle(cornerRadius: 12))
    )
    #expect(html.contains("border-radius: var(--container-shape-radius, 0px)"), "\(html)")
  }

  @Test
  func aSecondBackgroundStillTakesTheContainersCorners() {
    let html = StaticHTMLFiberRenderer().render(
      VStack { Text("Card").background(Color.red).background(Color.blue) }.containerShape(RoundedRectangle(cornerRadius: 12))
    )
    #expect(html.contains("border-radius: 12px"), "\(html)")
  }
}

/// `listItemTint(_:)` tints a row's icon over the app's tint, as Food Truck's grey city rows on iPad.
@Suite
@MainActor
struct ListItemTintTests {
  @Test
  func aRowCarriesItsTintForItsIcon() {
    let html = StaticHTMLFiberRenderer().render(
      List { Label("Cupertino", systemImage: "building.2").listItemTint(.secondary) }
    )
    #expect(html.contains("--list-item-tint: \(Color.secondary.cssValue)"), "\(html)")
  }
}
