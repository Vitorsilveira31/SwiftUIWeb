import SwiftUI

/// Study 06: a triangle sliding sideways. Its drawn edges and its exclusion are the same three points.
struct TriangleScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        let s = context.proseWidth / WrapSpace.logicalWidth
        let left = (100 + abs((context.elapsedMs / 24).truncatingRemainder(dividingBy: 480) - 240)) * s
        let top = 95 * s
        let points = [
            CGPoint(x: left, y: top),
            CGPoint(x: left + 170 * s, y: top + 105 * s),
            CGPoint(x: left, y: top + 210 * s),
        ]
        return [WrapExclusion.polygon("triangle", points, margin: 10, tint: .sage)]
    }
}
