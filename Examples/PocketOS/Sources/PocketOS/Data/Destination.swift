// Where a tile, a dock item or a notice leads.
enum Destination: Hashable, Sendable {
    case app(PhoneApp)
    case thread(String)
    case article(String)
}
