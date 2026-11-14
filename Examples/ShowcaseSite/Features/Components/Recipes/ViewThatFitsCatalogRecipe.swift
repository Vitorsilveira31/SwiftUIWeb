import SwiftUIWeb

enum ViewThatFitsCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "viewthatfits",
      name: "ViewThatFits",
      summary: CatalogText(
        pt: "Mostra a primeira opção que cabe no espaço que recebe.",
        en: "Shows the first option that fits in the space it is given."
      ),
      category: .layout,
      covers: ["ViewThatFits"],
      knobs: [
        CatalogKnob(id: "width", label: CatalogText(pt: "Largura", en: "Width"), kind: .number(range: 80...320, step: 10, defaultValue: 240)),
      ],
      preview: { AnyView(ViewThatFitsCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder("ViewThatFits(in: .horizontal) {\n  Text(\"A long label that needs the full width\")\n  Text(\"Short label\")\n}")
        let width = CatalogCodeBuilder.number(values.number("width"))
        code.modifier("frame(width: \(width))")
        code.modifier("background(Color.blue.opacity(0.15))")
        return code.text
      }
    )
  }
}
