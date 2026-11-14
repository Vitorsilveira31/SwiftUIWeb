import SwiftUIWeb

/// The live `List` of the catalog, in the list style the knob picks. The list has a fixed height, so it scrolls.
struct ListCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    Group {
      switch values.choice("style", in: ListCatalogRecipe.styles) {
      case "plain":
        ListCatalogContent(values: values).listStyle(.plain)
      case "inset":
        ListCatalogContent(values: values).listStyle(.inset)
      case "insetGrouped":
        ListCatalogContent(values: values).listStyle(.insetGrouped)
      case "grouped":
        ListCatalogContent(values: values).listStyle(.grouped)
      case "sidebar":
        ListCatalogContent(values: values).listStyle(.sidebar)
      default:
        ListCatalogContent(values: values).listStyle(.automatic)
      }
    }
    .frame(height: 200)
    .frame(maxWidth: 360)
  }
}
