import SwiftUIWeb

/// One entry of the catalog: what the component is, the knobs it offers, and the two things that must always agree, the
/// live view and the code that produces it. Both are built from the same knob values.
struct CatalogRecipe {
  let id: String
  let name: String
  let summary: CatalogText
  let category: CatalogCategory
  /// The public SwiftUIWeb types this entry shows (`VStack`, `HStack`). `Tools/audit-showcase-catalog.mjs` checks them
  /// against the public API, so a new component cannot ship without an entry or a reason it has none.
  let covers: [String]
  let knobs: [CatalogKnob]
  let preview: @MainActor (CatalogKnobValues) -> AnyView
  let code: (CatalogKnobValues) -> String
}
