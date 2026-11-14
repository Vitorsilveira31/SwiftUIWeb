// The fixtures on each page, by their fx-* identifier, in the order the pages show them.
// A fixture view names its tile with the same identifier, so a test can find it.
enum GalleryCatalog {
    static func fixtures(on page: GalleryPage) -> [String] {
        switch page {
        case .one:
            ["fx-shapes", "fx-units", "fx-transform", "fx-origin", "fx-icon", "fx-nested", "fx-nonscaling", "fx-style", "fx-ratio"]
        case .two:
            ["fx-color", "fx-boxcolor", "fx-spin"]
        case .three:
            ["fx-gradients", "fx-spread", "fx-area", "fx-opacity-restore", "fx-use", "fx-order",
             "fx-badge-#f43f5e", "fx-badge-#14b8a6", "fx-sprite"]
        case .four:
            ["fx-plot", "fx-bbox", "fx-rules"]
        case .five:
            ["fx-axis", "fx-baselines", "fx-runs"]
        case .six:
            ["fx-hit", "fx-bars"]
        case .seven:
            ["fx-arrows", "fx-orient"]
        case .eight:
            ["fx-mask-lum", "fx-mask-alpha", "fx-pattern-dots", "fx-pattern-hatch", "web-foreign"]
        case .nine:
            ["fx-blur", "fx-shadow", "fx-shadow-scaled", "fx-mask-gradient", "fx-drop-shadow-css", "fx-huge-region",
             "fx-matrix", "fx-blend", "fx-box-filter", "fx-image-filter", "fx-css", "fx-shape-ops", "fx-noise", "fx-light"]
        case .ten:
            ["fx-geometry", "fx-mix"]
        }
    }
}
