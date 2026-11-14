import SwiftUIWeb

enum GroupBoxCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "groupbox",
      name: "GroupBox",
      summary: CatalogText(
        pt: "Agrupa conteúdo dentro de uma caixa com título.",
        en: "Groups content inside a box with a title."
      ),
      category: .layout,
      covers: ["GroupBox"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "Details")),
        CatalogKnob(id: "content", label: CatalogText(pt: "Conteúdo", en: "Content"), kind: .text(defaultValue: "Content inside the box.")),
      ],
      preview: { AnyView(GroupBoxCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal(values.text("title"))
        let content = CatalogCodeBuilder.literal(values.text("content"))
        return CatalogCodeBuilder("GroupBox(label: Text(\(title))) {\n  Text(\(content))\n}").text
      }
    )
  }
}
