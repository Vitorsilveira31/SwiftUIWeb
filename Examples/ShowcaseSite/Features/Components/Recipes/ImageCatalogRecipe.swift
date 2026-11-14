import SwiftUIWeb

enum ImageCatalogRecipe {
  static let symbols = ["star.fill", "heart.fill", "bolt.fill", "globe", "swift"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "image",
      name: "Image",
      summary: CatalogText(
        pt: "Mostra uma imagem, aqui um símbolo do SF Symbols.",
        en: "Shows an image, here an SF Symbols symbol."
      ),
      category: .content,
      covers: ["Image"],
      knobs: [
        CatalogKnob(id: "symbol", label: CatalogText(pt: "Símbolo", en: "Symbol"), kind: .choice(options: symbols, defaultIndex: 0)),
        CatalogKnob(id: "size", label: CatalogText(pt: "Tamanho", en: "Size"), kind: .number(range: 16...96, step: 4, defaultValue: 48)),
        CatalogKnob(id: "color", label: CatalogText(pt: "Cor", en: "Color"), kind: .choice(options: CatalogTokens.colors, defaultIndex: 5)),
      ],
      preview: { AnyView(ImageCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder("Image(systemName: \(CatalogCodeBuilder.literal(values.choice("symbol", in: symbols))))")
        code.modifier("font(.system(size: \(CatalogCodeBuilder.number(values.number("size")))))")
        code.modifier("foregroundStyle(.\(values.choice("color", in: CatalogTokens.colors)))")
        return code.text
      }
    )
  }
}
