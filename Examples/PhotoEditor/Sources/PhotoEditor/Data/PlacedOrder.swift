/// A print order placed during this session.
struct PlacedOrder: Identifiable, Sendable {
    let id: Int
    let size: PrintSize
    let quantity: Int
    let totalCents: Int
}
