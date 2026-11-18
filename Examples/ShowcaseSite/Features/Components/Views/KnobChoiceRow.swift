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
      // An empty title, not `.labelsHidden()`: a menu picker with hidden labels is a bare piece of text, while one with an
      // empty title is a field with the border and the indicator that show it opens a menu (as `ComponentsCompactPicker`).
      // The screen reader still hears the knob's name.
      Picker(
        "",
        selection: Binding(get: { viewModel.values.choiceIndex(knob.id) }, set: { viewModel.set(knob.id, choiceIndex: $0) })
      ) {
        ForEach(options.indices, id: \.self) { index in Text(options[index]).tag(index) }
      }
      .pickerStyle(.menu)
      .accessibilityLabel(knob.label.resolved(language))
      .fixedSize()
    }
  }
}
