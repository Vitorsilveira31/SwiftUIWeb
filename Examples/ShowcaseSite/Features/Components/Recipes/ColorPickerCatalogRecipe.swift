import SwiftUIWeb

enum ColorPickerCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "colorpicker",
      name: "ColorPicker",
      summary: CatalogText(
        pt: "Escolhe uma cor numa paleta, com ou sem controle de opacidade.",
        en: "Picks a color from a palette, with or without an opacity control."
      ),
      category: .controls,
      covers: ["ColorPicker"],
      knobs: [
        CatalogKnob(id: "label", label: CatalogText(pt: "Rótulo", en: "Label"), kind: .text(defaultValue: "Color")),
        CatalogKnob(id: "opacity", label: CatalogText(pt: "Opacidade", en: "Opacity"), kind: .toggle(defaultValue: true)),
      ],
      preview: { AnyView(ColorPickerCatalogPreview(values: $0)) },
      code: { values in
        let label = CatalogCodeBuilder.literal(values.text("label"))
        let opacity = values.bool("opacity") ? "true" : "false"
        return CatalogCodeBuilder("ColorPicker(\(label), selection: $color, supportsOpacity: \(opacity))").text
      }
    )
  }
}
