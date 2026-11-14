import SwiftUIWeb

/// A knob that sets a piece of text.
struct KnobTextRow: View {
  let knob: CatalogKnob
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(knob.label.resolved(language))
      TextField(
        knob.label.resolved(language),
        text: Binding(get: { viewModel.values.text(knob.id) }, set: { viewModel.set(knob.id, text: $0) })
      )
      .textFieldStyle(.roundedBorder)
    }
  }
}
