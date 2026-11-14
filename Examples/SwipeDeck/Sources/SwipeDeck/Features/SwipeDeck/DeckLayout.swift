import SwiftUI

/// Sizes derived from the stage. The throw threshold and the off-screen distances come from the same size the
/// cards are laid out with.
struct DeckLayout: Equatable, Sendable {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    /// How far a drag must travel to count as a decision.
    let throwAt: CGFloat
    /// Far enough that a card tilted 20 degrees clears the stage sideways.
    let offX: CGFloat
    /// Far enough that a card clears the stage upwards.
    let offY: CGFloat

    init(stage: CGSize) {
        cardWidth = min(stage.width - 24, 420)
        cardHeight = max(0, stage.height - 16)
        throwAt = cardWidth * 0.3
        offX = (stage.width + cardWidth + stage.height) / 2
        offY = stage.height
    }

    /// How far a drag has gone towards a decision, 0 to 1.
    func progress(for translation: CGSize) -> CGFloat {
        min(1, max(0, max(abs(translation.width), -translation.height) / throwAt))
    }
}
