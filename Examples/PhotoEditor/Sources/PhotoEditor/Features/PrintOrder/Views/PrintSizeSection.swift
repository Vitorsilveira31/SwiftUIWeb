import SwiftUI

/// The print size and the quantity.
struct PrintSizeSection: View {
    let viewModel: PrintOrderViewModel

    var body: some View {
        Section(Strings.PrintOrder.printSection) {
            Picker(Strings.PrintOrder.size, selection: Binding(
                get: { viewModel.state.printSize },
                set: { viewModel.send(.selectSize($0)) }
            )) {
                ForEach(PrintSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("print-size")

            Stepper(
                Strings.PrintOrder.quantity(viewModel.state.quantity),
                value: Binding(
                    get: { viewModel.state.quantity },
                    set: { viewModel.send(.setQuantity($0)) }
                ),
                in: 1...10
            )
            .accessibilityIdentifier("quantity")
        }
    }
}
