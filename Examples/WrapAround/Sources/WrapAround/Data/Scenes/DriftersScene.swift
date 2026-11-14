import Foundation
import SwiftUI

/// Study 02: six discs in a 656 x 440 box, moved in fixed 16 ms steps with wall reflection and elastic
/// collisions. The clock picks how many steps to replay, so a 60-second cycle runs back and forth without a jump.
struct DriftersScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        let radii: [CGFloat] = [43, 31, 24, 36, 20, 28]
        var p: [CGPoint] = [
            CGPoint(x: 160, y: 74), CGPoint(x: 426, y: 116), CGPoint(x: 315, y: 248),
            CGPoint(x: 540, y: 300), CGPoint(x: 92, y: 330), CGPoint(x: 440, y: 383),
        ]
        var v: [CGPoint] = [
            CGPoint(x: 1.1, y: 0.68), CGPoint(x: -0.85, y: 0.72), CGPoint(x: 1.02, y: -0.64),
            CGPoint(x: -0.62, y: -0.83), CGPoint(x: 1.22, y: -0.45), CGPoint(x: -0.82, y: -0.72),
        ]
        let ms = context.elapsedMs
        let phase = 15_000 + 15_000 * sin(max(ms, 0).truncatingRemainder(dividingBy: 60_000) * 2 * .pi / 60_000)
        for _ in 0..<Int(phase / 16) {
            for i in 0..<6 {
                p[i].x += v[i].x
                p[i].y += v[i].y
                if p[i].x < radii[i] { p[i].x = 2 * radii[i] - p[i].x; v[i].x = abs(v[i].x) }
                if p[i].x > 656 - radii[i] { p[i].x = 2 * (656 - radii[i]) - p[i].x; v[i].x = -abs(v[i].x) }
                if p[i].y < radii[i] { p[i].y = 2 * radii[i] - p[i].y; v[i].y = abs(v[i].y) }
                if p[i].y > 440 - radii[i] { p[i].y = 2 * (440 - radii[i]) - p[i].y; v[i].y = -abs(v[i].y) }
            }
            for i in 0..<6 {
                for j in (i + 1)..<6 {
                    let dx = p[j].x - p[i].x, dy = p[j].y - p[i].y
                    let reach = radii[i] + radii[j]
                    if abs(dx) >= reach || abs(dy) >= reach { continue }
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance >= reach || distance < 0.0001 { continue }
                    let nx = dx / distance, ny = dy / distance
                    let m1 = radii[i] * radii[i], m2 = radii[j] * radii[j]
                    let overlap = reach - distance
                    p[i].x -= nx * overlap * m2 / (m1 + m2)
                    p[i].y -= ny * overlap * m2 / (m1 + m2)
                    p[j].x += nx * overlap * m1 / (m1 + m2)
                    p[j].y += ny * overlap * m1 / (m1 + m2)
                    let closing = (v[j].x - v[i].x) * nx + (v[j].y - v[i].y) * ny
                    if closing < 0 {
                        let impulse = 2 * closing / (m1 + m2)
                        v[i].x += impulse * m2 * nx
                        v[i].y += impulse * m2 * ny
                        v[j].x -= impulse * m1 * nx
                        v[j].y -= impulse * m1 * ny
                    }
                }
            }
        }
        let s = context.proseWidth / WrapSpace.logicalWidth
        let tints: [WrapTint] = [.terracotta, .sage, .ochre, .teal, .clay, .slate]
        return (0..<6).map { i in
            WrapExclusion.disc(
                "drift-\(i + 1)",
                center: CGPoint(x: p[i].x * s, y: p[i].y * s),
                radius: radii[i] * s,
                margin: 8,
                tint: tints[i]
            )
        }
    }
}
