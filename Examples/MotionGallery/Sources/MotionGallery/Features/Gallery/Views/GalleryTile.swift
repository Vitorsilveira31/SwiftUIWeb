import SwiftUI

/// Draws the tile that a catalog entry names.
struct GalleryTile: View {
    let kind: GalleryTileKind

    var body: some View {
        switch kind {
        case .frames(let sequence, let cornerRadius):
            FrameTile(sequence: sequence, cornerRadius: cornerRadius)
        case .sweep:
            SweepTile()
        case .pulse:
            PulseTile()
        case .rotation:
            RotationTile()
        case .glow:
            GlowTile()
        case .steps:
            StepsTile()
        case .tour:
            TourTile()
        case .origin:
            OriginTile()
        case .held:
            HeldTile()
        }
    }
}
