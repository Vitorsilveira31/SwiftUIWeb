import SwiftUIWeb

enum TextFieldCatalogRecipe {
  static let styles = ["automatic", "roundedBorder", "plain"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "textfield",
      name: "TextField",
      summary: CatalogText(
        pt: "Recebe uma linha de texto digitada pela pessoa.",
        en: "Takes one line of text typed by the person."
      ),
      category: .controls,
      covers: ["TextField"],
      knobs: [
        CatalogKnob(id: "prompt", label: CatalogText(pt: "Texto de ajuda", en: "Prompt"), kind: .text(defaultValue: "Your name")),
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 1)),
        CatalogKnob(id: "disabled", label: CatalogText(pt: "Desativado", en: "Disabled"), kind: .toggle(defaultValue: false)),
      ],
      preview: { AnyView(TextFieldCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder("TextField(\(CatalogCodeBuilder.literal(values.text("prompt"))), text: $text)")
        code.modifier("textFieldStyle(.\(values.choice("style", in: styles)))")
        code.modifier("disabled(true)", if: values.bool("disabled"))
        return code.text
      }
    )
  }
}
