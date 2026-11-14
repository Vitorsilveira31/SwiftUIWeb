import SwiftUI

/// What a study needs to place its shapes for one frame.
struct WrapSceneContext: Sendable {
    /// Milliseconds of scene time.
    let elapsedMs: CGFloat
    /// Width of the prose column in points.
    let proseWidth: CGFloat
    /// Points per logical unit of the page.
    let scale: CGFloat
    let narrow: Bool
    /// The draggable discs, read by the drag study only.
    let orbs: [WrapOrb]
}
