import SwiftUI

/// The prices of the order: prints, shipping and the total.
struct PriceSummarySection: View {
    let viewModel: PrintOrderViewModel

    var body: some View {
        Section(Strings.PrintOrder.summarySection) {
            LabeledContent(Strings.PrintOrder.prints) {
                Text(viewModel.state.printsCents.dollarAmount, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .accessibilityIdentifier("prints-price")
            }
            LabeledContent(Strings.PrintOrder.shipping) {
                Text(viewModel.state.shippingCents.dollarAmount, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .accessibilityIdentifier("shipping-price")
            }
            LabeledContent(Strings.PrintOrder.total) {
                Text(viewModel.state.totalCents.dollarAmount, format: .currency(code: "USD"))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .accessibilityIdentifier("print-total")
            }
        }
    }
}
