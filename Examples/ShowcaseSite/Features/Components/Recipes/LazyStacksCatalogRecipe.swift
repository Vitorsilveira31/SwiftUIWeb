import SwiftUIWeb

enum LazyStacksCatalogRecipe {
  static let directions = ["LazyVStack", "LazyHStack"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "lazystacks",
      name: "LazyVStack / LazyHStack",
      summary: CatalogText(
        pt: "Empilha ou enfileira linhas dentro de uma ScrollView, criando cada uma só quando ela aparece.",
        en: "Stacks or lines up rows inside a ScrollView, creating each one only when it is shown."
      ),
      category: .collections,
      covers: ["LazyVStack", "LazyHStack"],
      knobs: [
        CatalogKnob(id: "direction", label: CatalogText(pt: "Direção", en: "Direction"), kind: .choice(options: directions, defaultIndex: 0)),
        CatalogKnob(id: "spacing", label: CatalogText(pt: "Espaço", en: "Spacing"), kind: .number(range: 0...40, step: 2, defaultValue: 8)),
        CatalogKnob(id: "rows", label: CatalogText(pt: "Linhas", en: "Rows"), kind: .number(range: 1...30, step: 1, defaultValue: 12)),
      ],
      preview: { AnyView(LazyStacksCatalogPreview(values: $0)) },
      code: { values in
        let vertical = values.choice("direction", in: directions) == "LazyVStack"
        let axis = vertical ? "vertical" : "horizontal"
        let stack = vertical ? "LazyVStack" : "LazyHStack"
        let spacing = CatalogCodeBuilder.number(values.number("spacing"))
        let rows = CatalogCodeBuilder.number(values.number("rows"))
        var code = CatalogCodeBuilder("ScrollView(.\(axis)) {\n  \(stack)(spacing: \(spacing)) {\n    ForEach(1...\(rows), id: \\.self) { number in Text(\"Row \\(number)\") }\n  }\n}")
        code.modifier("frame(height: 160)")
        code.modifier("frame(maxWidth: 360)")
        return code.text
      }
    )
  }
}
