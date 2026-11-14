import SwiftUIWeb

enum DividerCatalogRecipe {
  static let directions = ["VStack", "HStack"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "divider",
      name: "Divider",
      summary: CatalogText(
        pt: "Traça uma linha que separa views dentro de uma pilha.",
        en: "Draws a line that separates views inside a stack."
      ),
      category: .layout,
      covers: ["Divider"],
      knobs: [
        CatalogKnob(id: "direction", label: CatalogText(pt: "Direção", en: "Direction"), kind: .choice(options: directions, defaultIndex: 0)),
        CatalogKnob(id: "padding", label: CatalogText(pt: "Espaçamento", en: "Padding"), kind: .number(range: 0...32, step: 4, defaultValue: 8)),
      ],
      preview: { AnyView(DividerCatalogPreview(values: $0)) },
      code: { values in
        let stack = values.choice("direction", in: directions)
        let padding = CatalogCodeBuilder.number(values.number("padding"))
        return "\(stack) {\n  Text(\"A\")\n  Divider().padding(\(padding))\n  Text(\"B\")\n}"
      }
    )
  }
}
