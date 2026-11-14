import SwiftUIWeb

/// A knob that picks one word out of a list, the same words the code uses.
struct KnobChoiceRow: View {
  let knob: CatalogKnob
  let options: [String]
  let viewModel: ComponentsViewModel
  @Environment(\.siteLanguage) private var language

  var body: some View {
    HStack {
      Text(knob.label.resolved(language))
      Spacer()
      Picker(
        knob.label.resolved(language),
        selection: Binding(get: { viewModel.values.choiceIndex(knob.id) }, set: { viewModel.set(knob.id, choiceIndex: $0) })
      ) {
        ForEach(options.indices, id: \.self) { index in Text(options[index]).tag(index) }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .fixedSize()
    }
  }
}
