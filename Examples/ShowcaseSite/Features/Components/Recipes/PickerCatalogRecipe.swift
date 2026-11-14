import SwiftUIWeb

enum PickerCatalogRecipe {
  static let styles = ["menu", "segmented", "inline"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "picker",
      name: "Picker",
      summary: CatalogText(
        pt: "Escolhe um valor entre várias opções.",
        en: "Chooses one value out of several options."
      ),
      category: .controls,
      covers: ["Picker"],
      knobs: [
        CatalogKnob(id: "label", label: CatalogText(pt: "Rótulo", en: "Label"), kind: .text(defaultValue: "Size")),
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 1)),
        CatalogKnob(id: "count", label: CatalogText(pt: "Opções", en: "Options"), kind: .number(range: 2...5, step: 1, defaultValue: 3)),
      ],
      preview: { AnyView(PickerCatalogPreview(values: $0)) },
      code: { values in
        let label = CatalogCodeBuilder.literal(values.text("label"))
        let count = CatalogCodeBuilder.number(values.number("count"))
        var code = CatalogCodeBuilder("Picker(\(label), selection: $selection) {\n  ForEach(1...\(count), id: \\.self) { Text(\"Option \\($0)\").tag($0) }\n}")
        code.modifier("pickerStyle(.\(values.choice("style", in: styles)))")
        return code.text
      }
    )
  }
}
