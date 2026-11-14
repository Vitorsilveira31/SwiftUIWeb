import SwiftUIWeb

enum StepperCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "stepper",
      name: "Stepper",
      summary: CatalogText(
        pt: "Aumenta e diminui um número com dois botões.",
        en: "Raises and lowers a number with two buttons."
      ),
      category: .controls,
      covers: ["Stepper"],
      knobs: [
        CatalogKnob(id: "label", label: CatalogText(pt: "Rótulo", en: "Label"), kind: .text(defaultValue: "Guests")),
        CatalogKnob(id: "step", label: CatalogText(pt: "Passo", en: "Step"), kind: .number(range: 1...5, step: 1, defaultValue: 1)),
        CatalogKnob(id: "maximum", label: CatalogText(pt: "Máximo", en: "Maximum"), kind: .number(range: 5...50, step: 5, defaultValue: 10)),
      ],
      preview: { AnyView(StepperCatalogPreview(values: $0)) },
      code: { values in
        let label = CatalogCodeBuilder.literal("\(values.text("label")): ", endingWith: "count")
        let maximum = CatalogCodeBuilder.number(values.number("maximum"))
        let step = CatalogCodeBuilder.number(values.number("step"))
        return CatalogCodeBuilder("Stepper(\(label), value: $count, in: 0...\(maximum), step: \(step))").text
      }
    )
  }
}
