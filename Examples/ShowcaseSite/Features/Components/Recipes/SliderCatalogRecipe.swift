import SwiftUIWeb

enum SliderCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "slider",
      name: "Slider",
      summary: CatalogText(
        pt: "Escolhe um número dentro de um intervalo arrastando.",
        en: "Picks a number within a range by dragging."
      ),
      category: .controls,
      covers: ["Slider"],
      knobs: [
        CatalogKnob(id: "maximum", label: CatalogText(pt: "Máximo", en: "Maximum"), kind: .number(range: 10...200, step: 10, defaultValue: 100)),
        CatalogKnob(id: "step", label: CatalogText(pt: "Passo (0 = contínuo)", en: "Step (0 = continuous)"), kind: .number(range: 0...20, step: 5, defaultValue: 0)),
      ],
      preview: { AnyView(SliderCatalogPreview(values: $0)) },
      code: { values in
        let maximum = CatalogCodeBuilder.number(values.number("maximum"))
        let step = values.number("step")
        let stepArgument = step > 0 ? ", step: \(CatalogCodeBuilder.number(step))" : ""
        return CatalogCodeBuilder("Slider(value: $level, in: 0...\(maximum)\(stepArgument))").text
      }
    )
  }
}
