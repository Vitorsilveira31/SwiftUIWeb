import SwiftUIWeb

enum ButtonCatalogRecipe {
  static let styles = ["automatic", "bordered", "borderedProminent", "borderless", "plain"]
  static let roles = ["none", "destructive"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "button",
      name: "Button",
      summary: CatalogText(
        pt: "Dispara uma ação quando é tocado ou clicado.",
        en: "Triggers an action when tapped or clicked."
      ),
      category: .controls,
      covers: ["Button"],
      knobs: [
        CatalogKnob(id: "title", label: CatalogText(pt: "Título", en: "Title"), kind: .text(defaultValue: "Save")),
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 2)),
        CatalogKnob(id: "role", label: CatalogText(pt: "Papel", en: "Role"), kind: .choice(options: roles, defaultIndex: 0)),
        CatalogKnob(id: "disabled", label: CatalogText(pt: "Desativado", en: "Disabled"), kind: .toggle(defaultValue: false)),
      ],
      preview: { AnyView(ButtonCatalogPreview(values: $0)) },
      code: { values in
        let title = CatalogCodeBuilder.literal(values.text("title"))
        let destructive = values.choice("role", in: roles) == "destructive"
        var code = CatalogCodeBuilder(destructive ? "Button(\(title), role: .destructive) { }" : "Button(\(title)) { }")
        code.modifier("buttonStyle(.\(values.choice("style", in: styles)))")
        code.modifier("disabled(true)", if: values.bool("disabled"))
        return code.text
      }
    )
  }
}
