import SwiftUIWeb

enum GeometryReaderCatalogRecipe {
  static func make() -> CatalogRecipe {
    CatalogRecipe(
      id: "geometryreader",
      name: "GeometryReader",
      summary: CatalogText(
        pt: "Lê o tamanho do espaço que recebe, para o conteúdo se adaptar a ele.",
        en: "Reads the size of the space it is given, so its content can adapt to it."
      ),
      category: .layout,
      covers: ["GeometryReader"],
      knobs: [
        CatalogKnob(id: "width", label: CatalogText(pt: "Largura", en: "Width"), kind: .number(range: 120...320, step: 10, defaultValue: 240)),
        CatalogKnob(id: "height", label: CatalogText(pt: "Altura", en: "Height"), kind: .number(range: 60...200, step: 10, defaultValue: 120)),
      ],
      preview: { AnyView(GeometryReaderCatalogPreview(values: $0)) },
      code: { values in
        var code = CatalogCodeBuilder("GeometryReader { proxy in\n  Text(\"\\(Int(proxy.size.width)) x \\(Int(proxy.size.height))\")\n}")
        let width = CatalogCodeBuilder.number(values.number("width"))
        let height = CatalogCodeBuilder.number(values.number("height"))
        code.modifier("frame(width: \(width), height: \(height))")
        code.modifier("background(Color.blue.opacity(0.15))")
        return code.text
      }
    )
  }
}
