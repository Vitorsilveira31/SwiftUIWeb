import SwiftUIWeb

enum GridCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "grid",
      name: "Grid",
      summary: CatalogText(
        pt: "Alinha views em linhas e colunas, com cada linha de células dentro de um GridRow.",
        en: "Aligns views in rows and columns, with each row of cells inside a GridRow."
      ),
      category: .collections,
      covers: ["Grid", "GridRow"],
      knobs: [
        CatalogKnob(id: "rows", label: CatalogText(pt: "Linhas", en: "Rows"), kind: .number(range: 1...5, step: 1, defaultValue: 3)),
        CatalogKnob(id: "columns", label: CatalogText(pt: "Colunas", en: "Columns"), kind: .number(range: 1...4, step: 1, defaultValue: 2)),
        CatalogKnob(id: "spacing", label: CatalogText(pt: "Espaço", en: "Spacing"), kind: .number(range: 0...24, step: 2, defaultValue: 8)),
      ],
      preview: { AnyView(GridCatalogPreview(values: $0)) },
      code: { values in
        let spacing = CatalogCodeBuilder.number(values.number("spacing"))
        let rows = CatalogCodeBuilder.number(values.number("rows"))
        let columns = CatalogCodeBuilder.number(values.number("columns"))
        var code = CatalogCodeBuilder("Grid(horizontalSpacing: \(spacing), verticalSpacing: \(spacing)) {\n  ForEach(1...\(rows), id: \\.self) { row in\n    GridRow {\n      ForEach(1...\(columns), id: \\.self) { column in\n        Text(\"\\(row).\\(column)\").padding(8).background(Color.blue.opacity(0.12))\n      }\n    }\n  }\n}")
        code.modifier("frame(maxWidth: 360)")
        return code.text
      }
    )
  }
}
