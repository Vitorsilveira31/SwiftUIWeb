import SwiftUIWeb

/// The live `GroupBox` of the catalog: a title above a box that holds the content text.
struct GroupBoxCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    GroupBox(label: Text(values.text("title"))) {
      Text(values.text("content"))
    }
    .frame(maxWidth: 360)
  }
}
