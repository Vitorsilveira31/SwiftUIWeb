import SwiftUIWeb

enum ShapesCatalogRecipe {
  static let shapes = ["Rectangle", "RoundedRectangle", "Circle", "Capsule", "Ellipse"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "shapes",
      name: "Shapes",
      summary: CatalogText(
        pt: "Desenha formas preenchidas e com borda, que também servem de fundo.",
        en: "Draws filled and outlined shapes, which also work as backgrounds."
      ),
      category: .content,
      covers: ["Rectangle", "RoundedRectangle", "Circle", "Capsule", "Ellipse"],
      knobs: [
        CatalogKnob(id: "shape", label: CatalogText(pt: "Forma", en: "Shape"), kind: .choice(options: shapes, defaultIndex: 1)),
        CatalogKnob(id: "color", label: CatalogText(pt: "Cor", en: "Color"), kind: .choice(options: CatalogTokens.colors, defaultIndex: 2)),
        CatalogKnob(id: "stroke", label: CatalogText(pt: "Espessura da borda", en: "Stroke width"), kind: .number(range: 1...12, step: 1, defaultValue: 2)),
      ],
      preview: { AnyView(ShapesCatalogPreview(values: $0)) },
      code: { values in
        let shape = values.choice("shape", in: shapes)
        let component = shape == "RoundedRectangle" ? "RoundedRectangle(cornerRadius: 16)" : "\(shape)()"
        var code = CatalogCodeBuilder(component)
        code.modifier("fill(.\(values.choice("color", in: CatalogTokens.colors)))")
        code.modifier("stroke(.primary, lineWidth: \(CatalogCodeBuilder.number(values.number("stroke"))))")
        code.modifier("frame(width: 120, height: 72)")
        return code.text
      }
    )
  }
}
