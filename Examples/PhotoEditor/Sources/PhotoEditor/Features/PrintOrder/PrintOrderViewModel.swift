import Observation

/// The print order: its size, quantity and destination, the price, and the orders placed.
@Observable
@MainActor
final class PrintOrderViewModel {
    struct State {
        var printSize: PrintSize = .fiveBySeven
        var quantity = 1
        var country: Country = .unitedStates
        var shipping: ShippingOption = .standard
        var orders: [PlacedOrder] = []

        var printsCents: Int { printSize.priceCents * quantity }

        var shippingCents: Int {
            if shipping == .express, let express = country.expressShippingCents { return express }
            return country.standardShippingCents
        }

        var totalCents: Int { printsCents + shippingCents }
    }

    enum Action {
        case selectSize(PrintSize)
        case setQuantity(Int)
        case selectCountry(Country)
        case selectShipping(ShippingOption)
        case placeOrder
    }

    private(set) var state: State

    init(initialState: State = .init()) {
        state = initialState
    }

    func send(_ action: Action) {
        switch action {
        case .selectSize(let size):
            state.printSize = size
        case .setQuantity(let quantity):
            state.quantity = quantity
        case .selectCountry(let country):
            state.country = country
        case .selectShipping(let option):
            state.shipping = option
        case .placeOrder:
            state.orders.append(PlacedOrder(
                id: state.orders.count + 1,
                size: state.printSize,
                quantity: state.quantity,
                totalCents: state.totalCents
            ))
        }
    }
}
