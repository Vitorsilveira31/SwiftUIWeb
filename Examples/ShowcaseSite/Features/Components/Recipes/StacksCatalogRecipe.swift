import SwiftUIWeb

enum StacksCatalogRecipe {
  static let directions = ["VStack", "HStack"]
  static let alignments = ["start", "center", "end"]

  static func horizontal(_ token: String) -> HorizontalAlignment {
    token == "start" ? .leading : (token == "end" ? .trailing : .center)
  }

  static func vertical(_ token: String) -> VerticalAlignment {
    token == "start" ? .top : (token == "end" ? .bottom : .center)
  }

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "stacks",
      name: "VStack / HStack",
      summary: CatalogText(
        pt: "Empilha views na vertical ou enfileira na horizontal.",
        en: "Stacks views vertically or lines them up horizontally."
      ),
      category: .layout,
      covers: ["VStack", "HStack"],
      knobs: [
        CatalogKnob(id: "direction", label: CatalogText(pt: "Direção", en: "Direction"), kind: .choice(options: directions, defaultIndex: 0)),
        CatalogKnob(id: "alignment", label: CatalogText(pt: "Alinhamento", en: "Alignment"), kind: .choice(options: alignments, defaultIndex: 0)),
        CatalogKnob(id: "spacing", label: CatalogText(pt: "Espaço", en: "Spacing"), kind: .number(range: 0...40, step: 2, defaultValue: 8)),
      ],
      preview: { AnyView(StacksCatalogPreview(values: $0)) },
      code: { values in
        let vertical = values.choice("direction", in: directions) == "VStack"
        let token = values.choice("alignment", in: alignments)
        let alignment = vertical ? (token == "start" ? "leading" : (token == "end" ? "trailing" : "center")) : (token == "start" ? "top" : (token == "end" ? "bottom" : "center"))
        let spacing = CatalogCodeBuilder.number(values.number("spacing"))
        return "\(vertical ? "VStack" : "HStack")(alignment: .\(alignment), spacing: \(spacing)) {\n  Box(\"A\")\n  Box(\"B\")\n  Box(\"C\")\n}"
      }
    )
  }
}
