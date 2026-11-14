import SwiftUI

/// The destination, and the shipping choice where the destination offers express.
struct ShipToSection: View {
    let viewModel: PrintOrderViewModel

    var body: some View {
        Section(Strings.PrintOrder.shipToSection) {
            Picker(Strings.PrintOrder.country, selection: Binding(
                get: { viewModel.state.country },
                set: { viewModel.send(.selectCountry($0)) }
            )) {
                ForEach(Country.allCases) { country in
                    Text(country.title).tag(country)
                }
            }
            .accessibilityIdentifier("country")

            if viewModel.state.country.expressShippingCents != nil {
                Picker(Strings.PrintOrder.shipping, selection: Binding(
                    get: { viewModel.state.shipping },
                    set: { viewModel.send(.selectShipping($0)) }
                )) {
                    ForEach(ShippingOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("shipping")
            }
        }
    }
}
