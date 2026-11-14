import SwiftUIWeb

enum SecureFieldCatalogRecipe {
  /// `roundedBorder` is not offered: the framework draws no difference for it on a secure field.
  static let styles = ["automatic", "plain"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "securefield",
      name: "SecureField",
      summary: CatalogText(
        pt: "Recebe uma senha ou outro texto secreto, que fica escondido enquanto é digitado.",
        en: "Takes a password or other secret text, hidden on screen while it is typed."
      ),
      category: .controls,
      covers: ["SecureField"],
      knobs: [
        CatalogKnob(id: "prompt", label: CatalogText(pt: "Texto de ajuda", en: "Prompt"), kind: .text(defaultValue: "Enter your password")),
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 0)),
        CatalogKnob(id: "disabled", label: CatalogText(pt: "Desativado", en: "Disabled"), kind: .toggle(defaultValue: false)),
      ],
      preview: { AnyView(SecureFieldCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal("Password")
        let prompt = CatalogCodeBuilder.literal(values.text("prompt"))
        var code = CatalogCodeBuilder("SecureField(\(title), text: $password, prompt: Text(\(prompt)))")
        code.modifier("textFieldStyle(.\(values.choice("style", in: styles)))")
        code.modifier("disabled(true)", if: values.bool("disabled"))
        return code.text
      }
    )
  }
}
