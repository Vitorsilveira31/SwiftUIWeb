import SwiftUIWeb

enum FormCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "form",
      name: "Form",
      summary: CatalogText(
        pt: "Agrupa controles de entrada em seções, como numa tela de ajustes.",
        en: "Groups input controls into sections, like a settings screen."
      ),
      category: .collections,
      covers: ["Form", "Section"],
      knobs: [
        CatalogKnob(id: "header", label: CatalogText(pt: "Cabeçalho", en: "Header"), kind: .text(defaultValue: "Settings")),
        CatalogKnob(id: "rows", label: CatalogText(pt: "Linhas", en: "Rows"), kind: .number(range: 1...4, step: 1, defaultValue: 2)),
      ],
      preview: { AnyView(FormCatalogPreview(values: $0)) },
      code: { values in
        let header = CatalogCodeBuilder.literal(values.text("header"))
        let count = Int(values.number("rows"))
        var rows = ""
        for number in 1...count {
          if number > 1 { rows += "\n" }
          rows += row(number)
        }
        return "Form {\n  Section(\(header)) {\n\(rows)\n  }\n}"
      }
    )
  }

  /// The code of one row: the odd rows are a `Toggle`, the even rows a `TextField`, as the live rows are.
  static func row(_ number: Int) -> String {
    number % 2 == 1 ? "    Toggle(\"Option \(number)\", isOn: $isOn)" : "    TextField(\"Option \(number)\", text: $text)"
  }
}
