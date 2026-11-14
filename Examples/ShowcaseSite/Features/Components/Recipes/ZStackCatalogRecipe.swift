import SwiftUIWeb

enum ZStackCatalogRecipe {
  static let alignments = ["center", "topLeading", "bottomTrailing"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "zstack",
      name: "ZStack",
      summary: CatalogText(
        pt: "Sobrepõe views no mesmo lugar, uma sobre a outra.",
        en: "Overlays views in the same place, one on top of the other."
      ),
      category: .layout,
      covers: ["ZStack"],
      knobs: [
        CatalogKnob(id: "alignment", label: CatalogText(pt: "Alinhamento", en: "Alignment"), kind: .choice(options: alignments, defaultIndex: 0)),
        CatalogKnob(id: "offset", label: CatalogText(pt: "Deslocamento", en: "Offset"), kind: .number(range: 0...40, step: 4, defaultValue: 16)),
      ],
      preview: { AnyView(ZStackCatalogPreview(values: $0)) },
      code: { values in
        let alignment = values.choice("alignment", in: alignments)
        let offset = CatalogCodeBuilder.number(values.number("offset"))
        return "ZStack(alignment: .\(alignment)) {\n  Box(\"A\")\n  Box(\"B\")\n  Box(\"C\").offset(x: \(offset))\n}"
      }
    )
  }
}
