/// Every user-visible string of the app.
enum Strings {
    enum Gallery {
        static let title = "Canvas Gallery"
        static let page = "Page"
        static let backdrop = "Backdrop"

        static func step(_ count: Int) -> String {
            "Step \(count)"
        }
    }
}
