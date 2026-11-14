import SwiftUI

/// Study 04: a single disc travelling on two triangle-wave paths.
struct BallScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        let ms = context.elapsedMs
        let s = context.proseWidth / WrapSpace.logicalWidth
        let x = (96 + abs((ms / 10).truncatingRemainder(dividingBy: 970) - 485)) * s
        let y = (86 + abs((ms / 18).truncatingRemainder(dividingBy: 520) - 260)) * s
        return [WrapExclusion.disc("ball", center: CGPoint(x: x, y: y), radius: 56 * s, margin: 10, tint: .terracotta)]
    }
}
