import SwiftUI

/// Study 01: the draggable discs, at the positions the view model holds, scaled to the column.
struct DragScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        context.orbs.enumerated().map { index, orb in
            WrapExclusion.disc(
                "orb-\(index + 1)",
                center: CGPoint(
                    x: (orb.x + orb.diameter / 2) * context.scale,
                    y: (orb.y + orb.diameter / 2) * context.scale
                ),
                radius: orb.diameter / 2 * context.scale,
                margin: 8,
                tint: orb.tint
            )
        }
    }
}
