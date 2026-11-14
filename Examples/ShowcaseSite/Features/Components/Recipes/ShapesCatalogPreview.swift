import SwiftUIWeb

/// The live shape of the catalog: the one the knob picks, painted the way the code says.
struct ShapesCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    switch values.choice("shape", in: ShapesCatalogRecipe.shapes) {
    case "Rectangle":
      ShapesCatalogPaint(shape: Rectangle(), values: values)
    case "Circle":
      ShapesCatalogPaint(shape: Circle(), values: values)
    case "Capsule":
      ShapesCatalogPaint(shape: Capsule(), values: values)
    case "Ellipse":
      ShapesCatalogPaint(shape: Ellipse(), values: values)
    default:
      ShapesCatalogPaint(shape: RoundedRectangle(cornerRadius: 16), values: values)
    }
  }
}
