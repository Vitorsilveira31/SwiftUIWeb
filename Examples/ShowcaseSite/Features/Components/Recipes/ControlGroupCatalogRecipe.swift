import SwiftUIWeb

enum ControlGroupCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "controlgroup",
      name: "ControlGroup",
      summary: CatalogText(
        pt: "Agrupa botões relacionados numa mesma linha.",
        en: "Groups related buttons on one line."
      ),
      category: .controls,
      covers: ["ControlGroup"],
      knobs: [
        CatalogKnob(id: "label", label: CatalogText(pt: "Rótulo", en: "Label"), kind: .text(defaultValue: "Actions")),
        CatalogKnob(id: "count", label: CatalogText(pt: "Botões", en: "Buttons"), kind: .number(range: 2...4, step: 1, defaultValue: 3)),
      ],
      preview: { AnyView(ControlGroupCatalogPreview(values: $0)) },
      code: { values in
        let label = CatalogCodeBuilder.literal(values.text("label"))
        let count = CatalogCodeBuilder.number(values.number("count"))
        return CatalogCodeBuilder("ControlGroup(\(label)) {\n  ForEach(1...\(count), id: \\.self) { number in\n    Button(\"\\(number)\") { }\n  }\n}").text
      }
    )
  }
}
