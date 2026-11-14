import SwiftUI

/// The print form: what to print, where it goes, what it costs, and the place-order button.
struct PrintOrderForm: View {
    let viewModel: PrintOrderViewModel

    var body: some View {
        Form {
            PrintSizeSection(viewModel: viewModel)
            ShipToSection(viewModel: viewModel)
            PriceSummarySection(viewModel: viewModel)

            Section {
                Button(Strings.PrintOrder.placeOrder) {
                    viewModel.send(.placeOrder)
                }
                .accessibilityIdentifier("place-order")
            }

            if !viewModel.state.orders.isEmpty {
                OrdersSection(viewModel: viewModel)
            }
        }
    }
}
