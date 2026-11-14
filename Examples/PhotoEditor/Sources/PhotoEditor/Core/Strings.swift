/// Every user-visible string of the app, grouped by feature. Format strings and accessibility identifiers stay
/// where they are used.
enum Strings {
    static let appTitle = "Photo Editor"

    enum Common {
        static let cancel = "Cancel"
    }

    enum Editor {
        static let choosePhoto = "Choose Photo"
        static let editHeading = "Edit"
        static func edited(_ count: Int) -> String {
            "Edited \(count) \(count == 1 ? "time" : "times")"
        }
        static let rotate = "Rotate 90°"
        static let rotateLabel = "Rotate the photo 90 degrees clockwise"
        static let reset = "Reset"
        static let resetLabel = "Reset zoom, rotation, position, crop and filters"
        static let undo = "Undo"
        static let filters = "Filters"
        static let adjust = "Adjust"
        static let photo = "Photo"
        static let takePhoto = "Take Photo"
        static let recentPhotos = "Recent Photos"
        static let orderPrint = "Order a Print"
        static let saveToPhotos = "Save to Photos"
        static let export = "Export"
        static let cropCorner = "Crop corner"
        static let sharePreview = "Edited photo"
    }

    enum Adjustment {
        static let brightness = "Brightness"
        static let contrast = "Contrast"
        static let saturation = "Saturation"
        static let hue = "Hue rotation"
        static let blur = "Blur"
        static let grayscale = "Grayscale"
    }

    enum Preset {
        static let original = "Original"
        static let vivid = "Vivid"
        static let mono = "Mono"
        static let fade = "Fade"
        static let dream = "Dream"
        static let cool = "Cool"
    }

    enum Sheets {
        enum Camera {
            static let navTitle = "Camera"
            static let unavailableTitle = "Camera unavailable"
            static let unavailableDescription = "SwiftUI has no camera viewfinder. Close this sheet and choose a photo from your library, or take one with the system camera and pick it."
        }

        enum Recents {
            static let navTitle = "Recent Photos"
            static let unavailableTitle = "Recent photos unavailable"
            static let unavailableDescription = "A SwiftUI app can't list the photo library itself. Choose a photo from the library, and it opens in the editor."
            static let chooseFromLibrary = "Choose from Library"
        }

        enum Save {
            static let navTitle = "Save to Photos"
            static let unavailableTitle = "Can't save to Photos"
            static let unavailableDescription = "SwiftUI has no API to add a photo to the library. Use Export, then choose Save Image in the share sheet."
        }
    }

    enum PrintOrder {
        static let navTitle = "Order a Print"
        static let printSection = "Print"
        static let size = "Size"
        static func quantity(_ count: Int) -> String {
            "Quantity: \(count)"
        }
        static let shipToSection = "Ship to"
        static let country = "Country"
        static let shipping = "Shipping"
        static let summarySection = "Summary"
        static let prints = "Prints"
        static let total = "Total"
        static let placeOrder = "Place Order"
        static let ordersSection = "Orders"
        static func orderLine(_ size: String, _ quantity: Int) -> String {
            "\(size) × \(quantity)"
        }
        static let close = "Close"
    }

    enum Country {
        static let unitedStates = "United States"
        static let canada = "Canada"
        static let unitedKingdom = "United Kingdom"
    }

    enum Shipping {
        static let standard = "Standard"
        static let express = "Express"
    }
}
