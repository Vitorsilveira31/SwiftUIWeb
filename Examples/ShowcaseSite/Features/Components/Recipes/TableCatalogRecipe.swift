import SwiftUIWeb

enum TableCatalogRecipe {
  static let styles = ["automatic", "inset", "bordered"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "table",
      name: "Table",
      summary: CatalogText(
        pt: "Mostra linhas e colunas de dados, em um dos estilos de tabela do SwiftUI.",
        en: "Shows rows and columns of data, in one of SwiftUI's table styles."
      ),
      category: .collections,
      covers: ["Table", "TableColumn"],
      knobs: [
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 0)),
        CatalogKnob(id: "rows", label: CatalogText(pt: "Linhas", en: "Rows"), kind: .number(range: 2...6, step: 1, defaultValue: 3)),
      ],
      preview: { AnyView(TableCatalogPreview(values: $0)) },
      code: { values in
        let rows = CatalogCodeBuilder.number(values.number("rows"))
        var code = CatalogCodeBuilder("Table(rows.prefix(\(rows))) {\n  TableColumn(\"Name\", value: \\.name)\n  TableColumn(\"Role\", value: \\.role)\n}")
        code.modifier("tableStyle(.\(values.choice("style", in: styles)))")
        code.modifier("frame(maxWidth: 360)")
        return code.text
      }
    )
  }
}
