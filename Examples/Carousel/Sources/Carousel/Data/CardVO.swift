/// One card in a strip. `hue` indexes the fixed content palette, so the card
/// colours are the same in both colour schemes.
struct CardVO: Identifiable, Hashable, Sendable {
    let n: Int
    let width: Double
    let hue: Int

    var id: String { "c\(n)" }
}
