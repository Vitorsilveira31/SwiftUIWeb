import SwiftUIWeb

enum LazyVGridCatalogRecipe {
  static let sizings = ["flexible", "adaptive"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "lazygrid",
      name: "LazyVGrid",
      summary: CatalogText(
        pt: "Dispõe células em colunas e cria cada uma só quando ela aparece ao rolar.",
        en: "Lays out cells in columns, creating each one only when it scrolls into view."
      ),
      category: .collections,
      covers: ["LazyVGrid"],
      knobs: [
        CatalogKnob(id: "sizing", label: CatalogText(pt: "Dimensionamento", en: "Sizing"), kind: .choice(options: sizings, defaultIndex: 0)),
        CatalogKnob(id: "columns", label: CatalogText(pt: "Colunas (flexível)", en: "Columns (flexible)"), kind: .number(range: 1...6, step: 1, defaultValue: 3)),
        CatalogKnob(id: "spacing", label: CatalogText(pt: "Espaço", en: "Spacing"), kind: .number(range: 0...24, step: 2, defaultValue: 8)),
      ],
      preview: { AnyView(LazyVGridCatalogPreview(values: $0)) },
      code: { values in
        let flexible = values.choice("sizing", in: sizings) == "flexible"
        let count = CatalogCodeBuilder.number(values.number("columns"))
        let columns = flexible ? "Array(repeating: GridItem(.flexible()), count: \(count))" : "[GridItem(.adaptive(minimum: 80))]"
        let spacing = CatalogCodeBuilder.number(values.number("spacing"))
        var code = CatalogCodeBuilder("ScrollView {\n  LazyVGrid(columns: \(columns), spacing: \(spacing)) {\n    ForEach(1...24, id: \\.self) { number in\n      Text(\"Item \\(number)\").padding(12).background(Color.blue.opacity(0.12))\n    }\n  }\n}")
        code.modifier("frame(height: 220)")
        code.modifier("frame(maxWidth: 360)")
        return code.text
      }
    )
  }
}
