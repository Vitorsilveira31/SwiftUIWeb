import SwiftUIWeb

enum LabelCatalogRecipe {
  static let symbols = ["folder", "tray", "paperplane", "trash"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "label",
      name: "Label",
      summary: CatalogText(
        pt: "Junta um título e um ícone na mesma linha.",
        en: "Pairs a title and an icon on one line."
      ),
      category: .content,
      covers: ["Label"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "Inbox")),
        CatalogKnob(id: "symbol", label: CatalogText(pt: "Símbolo", en: "Symbol"), kind: .choice(options: symbols, defaultIndex: 1)),
      ],
      preview: { AnyView(LabelCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder(
          "Label(\(CatalogCodeBuilder.literal(values.text("title"))), systemImage: \(CatalogCodeBuilder.literal(values.choice("symbol", in: symbols))))"
        )
        code.modifier("font(.title3)")
        return code.text
      }
    )
  }
}
