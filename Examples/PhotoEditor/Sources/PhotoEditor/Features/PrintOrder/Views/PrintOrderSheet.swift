import SwiftUI

/// Order a Print, as a sheet: the form in its own navigation stack, with a Close button.
struct PrintOrderSheet: View {
    let viewModel: PrintOrderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PrintOrderForm(viewModel: viewModel)
                .navigationTitle(Strings.PrintOrder.navTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.PrintOrder.close) { dismiss() }
                            .accessibilityIdentifier("close-print")
                    }
                }
        }
    }
}
