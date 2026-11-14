import SwiftUIWeb

enum ProgressCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "progressview",
      name: "ProgressView",
      summary: CatalogText(
        pt: "Mostra o andamento de uma tarefa, medido ou indeterminado.",
        en: "Shows how far a task has come, measured or indeterminate."
      ),
      category: .content,
      covers: ["ProgressView"],
      knobs: [
        CatalogKnob(id: "determinate", label: CatalogText(pt: "Com valor", en: "With a value"), kind: .toggle(defaultValue: true)),
        CatalogKnob(id: "value", label: CatalogText(pt: "Valor", en: "Value"), kind: .number(range: 0...1, step: 0.05, defaultValue: 0.6)),
        CatalogKnob(id: "tint", label: CatalogText(pt: "Cor", en: "Tint"), kind: .choice(options: CatalogTokens.colors, defaultIndex: 2)),
      ],
      preview: { AnyView(ProgressCatalogPreview(values: $0)) },
      code: { values in
        let component = values.bool("determinate") ? "ProgressView(value: \(CatalogCodeBuilder.number(values.number("value"))))" : "ProgressView()"
        var code = CatalogCodeBuilder(component)
        code.modifier("tint(.\(values.choice("tint", in: CatalogTokens.colors)))")
        return code.text
      }
    )
  }
}
