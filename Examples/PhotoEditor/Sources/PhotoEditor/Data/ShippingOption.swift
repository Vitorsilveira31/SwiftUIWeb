/// The shipping choice; only a country with express shipping offers the express option.
enum ShippingOption: String, CaseIterable, Identifiable, Sendable {
    case standard, express

    var id: String { rawValue }

    var title: String {
        self == .standard ? Strings.Shipping.standard : Strings.Shipping.express
    }
}
