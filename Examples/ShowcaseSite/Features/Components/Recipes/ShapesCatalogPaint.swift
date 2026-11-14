import SwiftUIWeb

/// A shape filled with the catalog's color and outlined with the stroke width the knob sets, in a box of the card's size.
struct ShapesCatalogPaint<Content: Shape>: View {
  let shape: Content
  let values: CatalogKnobValues

  var body: some View {
    shape
      .fill(CatalogTokens.color(values.choice("color", in: CatalogTokens.colors)))
      .stroke(.primary, lineWidth: values.number("stroke"))
      .frame(width: 120, height: 72)
  }
}
