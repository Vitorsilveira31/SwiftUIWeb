import SwiftUIWeb

enum GaugeCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "gauge",
      name: "Gauge",
      summary: CatalogText(
        pt: "Mostra um valor dentro de um intervalo, como carga ou capacidade.",
        en: "Shows a value within a range, such as charge or capacity."
      ),
      category: .content,
      covers: ["Gauge"],
      knobs: [
        CatalogKnob(id: "label", label: CatalogText(pt: "Rótulo", en: "Label"), kind: .text(defaultValue: "Battery")),
        CatalogKnob(id: "value", label: CatalogText(pt: "Valor", en: "Value"), kind: .number(range: 0...1, step: 0.05, defaultValue: 0.6)),
      ],
      preview: { AnyView(GaugeCatalogPreview(values: $0)) },
      code: { values in
        let value = CatalogCodeBuilder.number(values.number("value"))
        let label = CatalogCodeBuilder.literal(values.text("label"))
        return "Gauge(value: \(value)) {\n  Text(\(label))\n}"
      }
    )
  }
}
