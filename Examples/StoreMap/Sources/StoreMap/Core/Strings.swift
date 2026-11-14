/// Every user-visible literal of the app, grouped per feature.
enum Strings {
    enum Stores {
        static let title = "Stores"
        static let noStoreSelected = "No store selected"
        static let mapLabel = "Map of stores; the buttons below select a store without the map"
        static let zoomOut = "Zoom out"
        static let zoomIn = "Zoom in"

        static func selected(_ id: String) -> String {
            "Selected: \(id)"
        }

        static func pinsSelected(_ count: Int) -> String {
            "Pins selected on the map: \(count)"
        }

        static func zoom(_ level: Int) -> String {
            "Zoom: \(level)"
        }
    }
}
