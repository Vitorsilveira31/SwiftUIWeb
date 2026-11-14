import SwiftUIWeb

enum TextEditorCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "texteditor",
      name: "TextEditor",
      summary: CatalogText(
        pt: "Recebe um texto longo, com várias linhas, digitado pela pessoa.",
        en: "Takes a long text of several lines typed by the person."
      ),
      category: .controls,
      covers: ["TextEditor"],
      knobs: [
        CatalogKnob(id: "initial", label: CatalogText(pt: "Texto inicial", en: "Initial text"), kind: .text(defaultValue: "Notes for the team")),
        CatalogKnob(id: "height", label: CatalogText(pt: "Altura", en: "Height"), kind: .number(range: 60...240, step: 20, defaultValue: 120)),
      ],
      preview: { AnyView(TextEditorCatalogPreview(values: $0)) },
      code: { values in
        let initial = CatalogCodeBuilder.literal(values.text("initial"))
        let height = CatalogCodeBuilder.number(values.number("height"))
        var code = CatalogCodeBuilder("@State private var text = \(initial)\nTextEditor(text: $text)")
        code.modifier("frame(height: \(height))")
        return code.text
      }
    )
  }
}
