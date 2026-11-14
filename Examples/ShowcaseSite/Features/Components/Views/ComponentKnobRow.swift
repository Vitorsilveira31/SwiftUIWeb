import SwiftUIWeb

/// One knob, drawn by the control its kind calls for.
struct ComponentKnobRow: View {
  let knob: CatalogKnob
  let viewModel: ComponentsViewModel

  var body: some View {
    switch knob.kind {
    case .toggle:
      KnobToggleRow(knob: knob, viewModel: viewModel)
    case .choice(let options, _):
      KnobChoiceRow(knob: knob, options: options, viewModel: viewModel)
    case .number(let range, let step, _):
      KnobNumberRow(knob: knob, range: range, step: step, viewModel: viewModel)
    case .text:
      KnobTextRow(knob: knob, viewModel: viewModel)
    }
  }
}
