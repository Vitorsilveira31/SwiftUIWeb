import SwiftUIWeb

enum LinkCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "link",
      name: "Link",
      summary: CatalogText(
        pt: "Abre um endereço da web por meio de um link que o leitor pode seguir.",
        en: "Opens a web address through a link the reader can follow."
      ),
      category: .content,
      covers: ["Link"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "Documentation")),
        CatalogKnob(id: "destination", label: CatalogText(pt: "Endereço (URL)", en: "Destination (URL)"), kind: .text(defaultValue: "https://developer.apple.com/documentation/swiftui")),
      ],
      preview: { AnyView(LinkCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal(values.text("title"))
        let destination = CatalogCodeBuilder.literal(values.text("destination"))
        return "if let url = URL(string: \(destination)) { Link(\(title), destination: url) }"
      }
    )
  }
}
