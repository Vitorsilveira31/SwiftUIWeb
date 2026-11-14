import SwiftUIWeb

enum SpacerCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "spacer",
      name: "Spacer",
      summary: CatalogText(
        pt: "Ocupa o espaço livre entre views de uma pilha, com um tamanho mínimo.",
        en: "Takes up the free space between views in a stack, with a minimum size."
      ),
      category: .layout,
      covers: ["Spacer"],
      knobs: [
        CatalogKnob(id: "minLength", label: CatalogText(pt: "Tamanho mínimo", en: "Minimum length"), kind: .number(range: 0...120, step: 8, defaultValue: 24)),
        CatalogKnob(id: "fixed", label: CatalogText(pt: "Caixas fixas", en: "Fixed boxes"), kind: .toggle(defaultValue: false)),
      ],
      preview: { AnyView(SpacerCatalogPreview(values: $0)) },
      code: { values in
        let fixed = values.bool("fixed") ? ".fixedSize()" : ""
        let minLength = CatalogCodeBuilder.number(values.number("minLength"))
        return "HStack {\n  Box(\"A\")\(fixed)\n  Spacer(minLength: \(minLength))\n  Box(\"B\")\(fixed)\n}"
      }
    )
  }
}
