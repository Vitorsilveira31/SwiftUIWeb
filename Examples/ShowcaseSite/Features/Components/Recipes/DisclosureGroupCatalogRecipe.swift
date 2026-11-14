import SwiftUIWeb

enum DisclosureGroupCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "disclosuregroup",
      name: "DisclosureGroup",
      summary: CatalogText(
        pt: "Mostra um título que abre e fecha o conteúdo abaixo dele.",
        en: "Shows a title that opens and closes the content below it."
      ),
      category: .layout,
      covers: ["DisclosureGroup"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "Details")),
        CatalogKnob(id: "expanded", label: CatalogText(pt: "Começa aberto", en: "Starts expanded"), kind: .toggle(defaultValue: true)),
      ],
      preview: { AnyView(DisclosureGroupCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal(values.text("title"))
        let expanded = values.bool("expanded") ? "true" : "false"
        return "@State private var isExpanded = \(expanded)\nDisclosureGroup(\(title), isExpanded: $isExpanded) {\n  Text(\"Shown when expanded\")\n}"
      }
    )
  }
}
