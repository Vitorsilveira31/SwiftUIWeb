/// The tiles of the gallery in the reference's order: the image tiles, then the keyframe tiles.
enum GalleryCatalog {
    static let images: [GalleryEntry] = [
        GalleryEntry(label: Strings.Images.fourFrames, testId: "fx-gif", tile: .frames(.spin, cornerRadius: 0)),
        GalleryEntry(label: Strings.Images.threeFrames, testId: "fx-once", tile: .frames(.once, cornerRadius: 0)),
        GalleryEntry(label: Strings.Images.zeroDelays, testId: "fx-zero", tile: .frames(.zero, cornerRadius: 0)),
        GalleryEntry(label: Strings.Images.largeGif, testId: "fx-large", tile: .frames(.large, cornerRadius: 0)),
        GalleryEntry(label: Strings.Images.webpTwice, testId: "fx-webp", tile: .frames(.twice, cornerRadius: 0)),
        GalleryEntry(label: Strings.Images.webpAlpha, testId: "fx-alpha", tile: .frames(.alpha, cornerRadius: 0)),
        GalleryEntry(label: Strings.Images.rounded, testId: "fx-round", tile: .frames(.spin, cornerRadius: 16)),
    ]

    static let keyframes: [GalleryEntry] = [
        GalleryEntry(label: Strings.Keyframes.sweep, testId: "fx-sweep", tile: .sweep),
        GalleryEntry(label: Strings.Keyframes.pulse, testId: "fx-pulse", tile: .pulse),
        GalleryEntry(label: Strings.Keyframes.spin, testId: "fx-spin", tile: .rotation),
        GalleryEntry(label: Strings.Keyframes.glow, testId: "fx-glow", tile: .glow),
        GalleryEntry(label: Strings.Keyframes.steps, testId: "fx-steps", tile: .steps),
        GalleryEntry(label: Strings.Keyframes.tour, testId: "fx-tour", tile: .tour),
        GalleryEntry(label: Strings.Keyframes.origin, testId: "fx-origin", tile: .origin),
        GalleryEntry(label: Strings.Keyframes.held, testId: "fx-held", tile: .held),
    ]
}
