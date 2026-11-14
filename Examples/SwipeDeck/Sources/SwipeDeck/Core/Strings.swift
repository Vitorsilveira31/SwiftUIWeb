/// Every user-visible sentence of the screen, grouped by where it appears.
enum Strings {
    enum Deck {
        static let title = "Swipe Deck"
        static let undo = "Undo"
        static let nope = "Nope"
        static let superLike = "Super like"
        static let like = "Like"
        static let previousPhoto = "Previous photo"
        static let nextPhoto = "Next photo"
    }

    /// The verdict labels stamped across a card while it is dragged.
    enum Verdict {
        static let like = "LIKE"
        static let nope = "NOPE"
        static let superLike = "SUPER LIKE"
    }

    enum Card {
        static func photoOf(_ name: String) -> String {
            "Photo of \(name)"
        }

        static func summary(_ name: String, _ age: Int) -> String {
            "\(name), \(age)"
        }

        static func distance(_ miles: Int) -> String {
            "\(miles) \(miles == 1 ? "mile" : "miles") away"
        }
    }

    enum Empty {
        static let title = "You've seen everyone nearby"
        static let message = "Check back later, or start over from the top of the deck."
        static let startOver = "Start over"
    }

    enum Match {
        static let title = "It's a match!"
        static let keepSwiping = "Keep swiping"

        static func likesYou(_ name: String) -> String {
            "You and \(name) like each other."
        }
    }
}
