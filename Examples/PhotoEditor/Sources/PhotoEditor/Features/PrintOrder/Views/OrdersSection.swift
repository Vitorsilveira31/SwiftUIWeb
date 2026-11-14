import SwiftUI

/// The orders placed in this session, one line each.
struct OrdersSection: View {
    let viewModel: PrintOrderViewModel

    var body: some View {
        Section(Strings.PrintOrder.ordersSection) {
            ForEach(viewModel.state.orders) { order in
                LabeledContent(Strings.PrintOrder.orderLine(order.size.label, order.quantity)) {
                    Text(order.totalCents.dollarAmount, format: .currency(code: "USD"))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("order-\(order.id)")
            }
        }
    }
}
