extension Strings {
    enum Reader {
        static let title = "Reader"
        static let askPocket = "Ask Pocket"
        static let talkAboutThis = "Talk about this with Pocket"

        static func listKicker(_ section: String, _ minutes: Int) -> String {
            "\(section) · \(minutes) min"
        }

        static func byline(_ author: String, _ posted: String, _ minutes: Int) -> String {
            "\(author) · \(posted) · \(minutes) min read"
        }
    }
}
