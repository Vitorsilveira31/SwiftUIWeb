import SwiftUIWeb

/// The live `Menu` of the catalog; the number under it is the last item picked, zero before any pick.
struct MenuCatalogPreview: View {
  let values: CatalogKnobValues
  @State private var picked = 0

  var body: some View {
    VStack(spacing: 8) {
      MenuCatalogContent(title: values.text("title"), count: Int(values.number("count")), picked: $picked)
      Text("\(picked)").font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: 320)
  }
}
