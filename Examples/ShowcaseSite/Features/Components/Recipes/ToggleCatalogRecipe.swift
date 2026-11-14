import SwiftUIWeb

enum ToggleCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "toggle",
      name: "Toggle",
      summary: CatalogText(
        pt: "Liga e desliga um valor booleano.",
        en: "Switches a Boolean value on and off."
      ),
      category: .controls,
      covers: ["Toggle"],
      knobs: [
        CatalogKnob(id: "label", label: CatalogText(pt: "Rótulo", en: "Label"), kind: .text(defaultValue: "Notifications")),
        CatalogKnob(id: "disabled", label: CatalogText(pt: "Desativado", en: "Disabled"), kind: .toggle(defaultValue: false)),
      ],
      preview: { AnyView(ToggleCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder("Toggle(\(CatalogCodeBuilder.literal(values.text("label"))), isOn: $isOn)")
        code.modifier("disabled(true)", if: values.bool("disabled"))
        return code.text
      }
    )
  }
}
