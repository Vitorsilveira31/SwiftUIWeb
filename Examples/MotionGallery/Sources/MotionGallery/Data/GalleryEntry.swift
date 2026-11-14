import SwiftUI

/// What one tile draws. The view for each case is chosen in Features/Gallery/Views/GalleryTile.swift.
enum GalleryTileKind: Sendable {
    case frames(FrameSequence, cornerRadius: CGFloat)
    case sweep
    case pulse
    case rotation
    case glow
    case steps
    case tour
    case origin
    case held
}

/// One tile of the gallery: its caption, its accessibility identifier and what it draws.
struct GalleryEntry: Identifiable, Sendable {
    let label: String
    let testId: String
    let tile: GalleryTileKind

    var id: String { testId }
}
