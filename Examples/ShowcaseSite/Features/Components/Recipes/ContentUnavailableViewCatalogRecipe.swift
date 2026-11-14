import SwiftUIWeb

enum ContentUnavailableViewCatalogRecipe {
  static let symbols = ["tray", "magnifyingglass", "wifi.slash", "exclamationmark.triangle"]
  static let descriptionText = "Try another search."

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "contentunavailableview",
      name: "ContentUnavailableView",
      summary: CatalogText(
        pt: "Mostra um estado vazio ou de erro, com símbolo, título e descrição opcional.",
        en: "Shows an empty or error state, with a symbol, a title and an optional description."
      ),
      category: .content,
      covers: ["ContentUnavailableView"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "No Results")),
        CatalogKnob(id: "symbol", label: CatalogText(pt: "Símbolo", en: "Symbol"), kind: .choice(options: symbols, defaultIndex: 1)),
        CatalogKnob(id: "description", label: CatalogText(pt: "Descrição", en: "Description"), kind: .toggle(defaultValue: true)),
      ],
      preview: { AnyView(ContentUnavailableViewCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal(values.text("title"))
        let symbol = CatalogCodeBuilder.literal(values.choice("symbol", in: symbols))
        let description = values.bool("description") ? ", description: Text(\(CatalogCodeBuilder.literal(descriptionText)))" : ""
        return "ContentUnavailableView(\(title), systemImage: \(symbol)\(description))"
      }
    )
  }
}
