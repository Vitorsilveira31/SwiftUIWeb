// Every user-visible string of Pocket OS, grouped by feature. Text with values is a function.
enum Strings {
    enum Shell {
        static let title = "Pocket OS"
        static let lock = "Lock"
        static let home = "Home"

        static func unavailable(_ name: String) -> String {
            "\(name) isn’t in this demo yet"
        }
    }

    enum Lock {
        static let swipeUp = "Swipe up to unlock"
        static let clear = "Clear"
        static let flashlight = "Flashlight"
        static let camera = "Camera"
    }

    enum Home {
        static func highLow(_ high: Int, _ low: Int) -> String {
            "H \(high)°  L \(low)°"
        }

        static func readerKicker(_ section: String) -> String {
            "READER · \(section.uppercased())"
        }

        static func readerByline(_ author: String, _ minutes: Int) -> String {
            "\(author) · \(minutes) min"
        }
    }
}
