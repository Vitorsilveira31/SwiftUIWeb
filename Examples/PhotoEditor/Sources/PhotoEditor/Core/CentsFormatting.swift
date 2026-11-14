extension Int {
    /// An amount in cents, as dollars for a currency format.
    var dollarAmount: Double {
        Double(self) / 100
    }
}
