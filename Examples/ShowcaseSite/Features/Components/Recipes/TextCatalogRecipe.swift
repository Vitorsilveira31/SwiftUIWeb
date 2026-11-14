import SwiftUIWeb

enum TextCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "text",
      name: "Text",
      summary: CatalogText(
        pt: "Mostra uma ou mais linhas de texto somente leitura.",
        en: "Shows one or more lines of read-only text."
      ),
      category: .content,
      covers: ["Text"],
      knobs: [
        CatalogKnob(id: "content", label: CatalogText(pt: "Conteúdo", en: "Content"), kind: .text(defaultValue: "Hello, SwiftUIWeb")),
        CatalogKnob(id: "font", label: CatalogText(pt: "Fonte", en: "Font"), kind: .choice(options: CatalogTokens.fonts, defaultIndex: 1)),
        CatalogKnob(id: "bold", label: CatalogText(pt: "Negrito", en: "Bold"), kind: .toggle(defaultValue: false)),
        CatalogKnob(id: "color", label: CatalogText(pt: "Cor", en: "Color"), kind: .choice(options: CatalogTokens.colors, defaultIndex: 0)),
      ],
      preview: { AnyView(TextCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder("Text(\(CatalogCodeBuilder.literal(values.text("content"))))")
        code.modifier("font(.\(values.choice("font", in: CatalogTokens.fonts)))")
        code.modifier("fontWeight(.bold)", if: values.bool("bold"))
        let color = values.choice("color", in: CatalogTokens.colors)
        code.modifier("foregroundStyle(.\(color))", if: color != "primary")
        return code.text
      }
    )
  }
}
