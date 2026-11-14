import SwiftUIWeb

/// The live `DisclosureGroup` of the catalog. The knob only sets the state the group starts in, so each start is its own
/// view: flipping the knob starts a new one, in the new state.
struct DisclosureGroupCatalogPreview: View {
  let values: CatalogKnobValues

  var body: some View {
    if values.bool("expanded") {
      DisclosureGroupCatalogContent(title: values.text("title"), startsExpanded: true)
    } else {
      DisclosureGroupCatalogContent(title: values.text("title"), startsExpanded: false)
    }
  }
}
