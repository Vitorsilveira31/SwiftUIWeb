import SwiftUIWeb

enum MenuCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "menu",
      name: "Menu",
      summary: CatalogText(
        pt: "Reúne ações numa lista que abre ao ser tocada ou clicada.",
        en: "Groups actions in a list that opens when tapped or clicked."
      ),
      category: .controls,
      covers: ["Menu"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "Actions")),
        CatalogKnob(id: "count", label: CatalogText(pt: "Itens", en: "Items"), kind: .number(range: 1...4, step: 1, defaultValue: 3)),
      ],
      preview: { AnyView(MenuCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal(values.text("title"))
        let count = CatalogCodeBuilder.number(values.number("count"))
        return CatalogCodeBuilder("Menu(\(title)) {\n  ForEach(1...\(count), id: \\.self) { number in\n    Button(\"Item \\(number)\") { }\n  }\n}").text
      }
    )
  }
}
