/// The destinations the lab ships to, with the shipping price for each.
enum Country: String, CaseIterable, Identifiable, Sendable {
    case unitedStates, canada, unitedKingdom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unitedStates: Strings.Country.unitedStates
        case .canada: Strings.Country.canada
        case .unitedKingdom: Strings.Country.unitedKingdom
        }
    }

    var standardShippingCents: Int {
        switch self {
        case .unitedStates: 500
        case .canada: 900
        case .unitedKingdom: 1200
        }
    }

    /// Only the United States offers express shipping.
    var expressShippingCents: Int? {
        self == .unitedStates ? 1500 : nil
    }
}
