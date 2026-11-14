enum Strings {
    enum Cards {
        static let title = "Cards"
        static let far = "Far"
        static let feed = "Feed"
        static let strip = "Strip"
        static let eager = "Eager"
        static let virtualized = "Virtualized"
        static let down = "Down"
        static let top = "Top"
        static let stripFootnote = "A strip of 25,000 cards: only those near the port are built."
        static let ordinaryRow = "An ordinary row between the lists."

        static func post(_ number: Int) -> String {
            "Post \(number)"
        }

        static func card(_ number: Int) -> String {
            "Card \(number)"
        }
    }
}
