import SwiftUIWeb

enum ListCatalogRecipe {
  static let styles = ["automatic", "plain", "inset", "insetGrouped", "grouped", "sidebar"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "list",
      name: "List",
      summary: CatalogText(
        pt: "Mostra uma coluna de linhas roláveis, em um dos estilos de lista do SwiftUI.",
        en: "Shows a scrollable column of rows, in one of SwiftUI's list styles."
      ),
      category: .collections,
      covers: ["List"],
      knobs: [
        CatalogKnob(id: "style", label: CatalogText(pt: "Estilo", en: "Style"), kind: .choice(options: styles, defaultIndex: 1)),
        CatalogKnob(id: "rows", label: CatalogText(pt: "Linhas", en: "Rows"), kind: .number(range: 1...8, step: 1, defaultValue: 4)),
      ],
      preview: { AnyView(ListCatalogPreview(values: $0)) },
      code: { values in
        let rows = CatalogCodeBuilder.number(values.number("rows"))
        var code = CatalogCodeBuilder("List {\n  ForEach(1...\(rows), id: \\.self) { number in Text(\"Row \\(number)\") }\n}")
        code.modifier("listStyle(.\(values.choice("style", in: styles)))")
        code.modifier("frame(height: 200)")
        code.modifier("frame(maxWidth: 360)")
        return code.text
      }
    )
  }
}
