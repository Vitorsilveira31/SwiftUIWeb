import SwiftUIWeb

/// The live `Link` of the catalog. It is shown only while the destination text reads as a URL.
struct LinkCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if let destination = URL(string: values.text("destination")) {
      Link(values.text("title"), destination: destination)
    }
  }
}
