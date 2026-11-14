import SwiftUIWeb

enum ScrollViewCatalogRecipe {
  static let axes = ["vertical", "horizontal"]

  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "scrollview",
      name: "ScrollView",
      summary: CatalogText(
        pt: "Deixa o conteúdo rolar na vertical ou na horizontal quando ele não cabe na área.",
        en: "Lets content scroll vertically or horizontally when it does not fit the area."
      ),
      category: .collections,
      covers: ["ScrollView"],
      knobs: [
        CatalogKnob(id: "axis", label: CatalogText(pt: "Eixo", en: "Axis"), kind: .choice(options: axes, defaultIndex: 0)),
        CatalogKnob(id: "indicators", label: CatalogText(pt: "Mostrar indicadores", en: "Show indicators"), kind: .toggle(defaultValue: true)),
      ],
      preview: { AnyView(ScrollViewCatalogPreview(values: $0)) },
      code: { values in
        let axis = values.choice("axis", in: axes)
        let vertical = axis == "vertical"
        let stack = vertical ? "VStack(alignment: .leading, spacing: 8)" : "HStack(spacing: 8)"
        let indicators = values.bool("indicators") ? "visible" : "hidden"
        var code = CatalogCodeBuilder("ScrollView(.\(axis)) {\n  \(stack) {\n    ForEach(1...20, id: \\.self) { number in Text(\"Item \\(number)\") }\n  }\n}")
        code.modifier("scrollIndicators(.\(indicators))")
        code.modifier("frame(height: 160)")
        code.modifier("frame(maxWidth: 360)")
        return code.text
      }
    )
  }
}
