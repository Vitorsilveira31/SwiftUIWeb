import SwiftUIWeb

/// A knob that sets a number with a slider, the number shown beside it.
struct KnobNumberRow: View {
  let knob: CatalogKnob
  let range: ClosedRange<Double>
  let step: Double
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(knob.label.resolved(language))
        Spacer()
        Text(CatalogCodeBuilder.number(viewModel.values.number(knob.id))).monospacedDigit().foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(get: { viewModel.values.number(knob.id) }, set: { viewModel.set(knob.id, number: $0) }),
        in: range,
        step: step
      )
    }
  }
}
