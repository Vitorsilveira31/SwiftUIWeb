import SwiftUIWeb

/// A knob that switches something on or off.
struct KnobToggleRow: View {
  let knob: CatalogKnob
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    Toggle(
      knob.label.resolved(language),
      isOn: Binding(get: { viewModel.values.bool(knob.id) }, set: { viewModel.set(knob.id, bool: $0) })
    )
  }
}
