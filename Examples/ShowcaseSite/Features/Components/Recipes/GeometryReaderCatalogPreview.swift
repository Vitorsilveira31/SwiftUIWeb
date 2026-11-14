import SwiftUIWeb

/// The live `GeometryReader` of the catalog, in the frame the knobs set; its content prints the size it reads.
struct GeometryReaderCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    GeometryReader { proxy in
      Text("\(Int(proxy.size.width)) x \(Int(proxy.size.height))")
    }
    .frame(width: values.number("width"), height: values.number("height"))
    .background(Color.blue.opacity(0.15))
  }
}
