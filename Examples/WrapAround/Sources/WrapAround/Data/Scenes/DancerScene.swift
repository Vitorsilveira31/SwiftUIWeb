import Foundation
import SwiftUI

/// Study 03: a figure of fourteen pieces. Each filled limb and its exclusion are the same polygon.
struct DancerScene: WrapSceneGeometry {
    func parts(_ context: WrapSceneContext) -> [WrapExclusion] {
        let beat = max(context.elapsedMs, 0).truncatingRemainder(dividingBy: 24_000) / 1000 * 2 * .pi / 6
        let breath = sin(beat)
        let bend = (1 - cos(beat * 0.5)) * 0.5
        let lean = 0.10 * sin(beat - 0.4)
        let hip = CGPoint(x: 0, y: 221 + 10 * bend)
        let shoulder = CGPoint(x: -15 * breath, y: 141 + 10 * bend)
        let neck = CGPoint(x: shoulder.x - 3 * breath, y: 120 + 10 * bend)
        let head = CGPoint(x: neck.x - 3 * breath, y: 99 + 10 * bend)
        let ls = CGPoint(x: shoulder.x - 20, y: shoulder.y)
        let rs = CGPoint(x: shoulder.x + 20, y: shoulder.y)
        let le = joint(ls, 52, -1.65 - 0.8 * sin(beat - 0.5))
        let re = joint(rs, 52, 1.9 + 0.75 * sin(beat + 0.4))
        let lw = joint(le, 47, -1.1 - 1.1 * sin(beat - 0.9))
        let rw = joint(re, 47, 2.65 + 0.75 * sin(beat - 0.2))
        let lh = CGPoint(x: hip.x - 13, y: hip.y)
        let rh = CGPoint(x: hip.x + 13, y: hip.y)
        let lk = joint(lh, 77, -0.16 - 0.48 * bend + lean)
        let rk = joint(rh, 77, 0.16 + 0.48 * bend + lean)
        let la = joint(lk, 76, 0.10 + 0.48 * bend - lean)
        let ra = joint(rk, 76, -0.10 - 0.48 * bend - lean)

        let w = min(max(context.proseWidth, 240), 900)
        let s = min(max((w / WrapSpace.logicalWidth).squareRoot(), 0.58), 1)
        let offset = CGPoint(x: w / 2, y: -40 * s)
        func place(_ points: [CGPoint]) -> [CGPoint] {
            points.map { CGPoint(x: $0.x * s + offset.x, y: $0.y * s + offset.y) }
        }

        var parts: [WrapExclusion] = [
            WrapExclusion.disc("dancer-head", center: place([head])[0], radius: 19 * s, margin: 8, tint: .plum),
        ]
        let limbs: [(String, CGPoint, CGPoint, CGFloat)] = [
            ("neck", neck, shoulder, 8),
            ("upper-arm-left", ls, le, 8),
            ("forearm-left", le, lw, 6),
            ("upper-arm-right", rs, re, 8),
            ("forearm-right", re, rw, 6),
            ("thigh-left", lh, lk, 12),
            ("calf-left", lk, la, 8),
            ("thigh-right", rh, rk, 12),
            ("calf-right", rk, ra, 8),
            ("foot-left", la, CGPoint(x: la.x - 20, y: la.y + 5), 5),
            ("foot-right", ra, CGPoint(x: ra.x + 20, y: ra.y + 5), 5),
        ]
        for (name, a, b, r) in limbs {
            parts.append(WrapExclusion.polygon("dancer-\(name)", place(capsule(a, b, r)), margin: 8, tint: .plum))
        }
        let bodice = capsule(CGPoint(x: shoulder.x, y: shoulder.y + 3), CGPoint(x: hip.x, y: hip.y - 13), 17)
        parts.append(WrapExclusion.polygon("dancer-bodice", place(bodice), margin: 8, tint: .plum))

        let swing = 12 * sin(beat - 0.5)
        let skirt = [
            CGPoint(x: hip.x - 13, y: hip.y - 18),
            CGPoint(x: hip.x + 13, y: hip.y - 18),
            CGPoint(x: hip.x + 52 + swing, y: hip.y + 38),
            CGPoint(x: hip.x + 25 + swing, y: hip.y + 45),
            CGPoint(x: hip.x + swing, y: hip.y + 41),
            CGPoint(x: hip.x - 48 + swing, y: hip.y + 34),
        ]
        parts.append(WrapExclusion.polygon("dancer-skirt", place(skirt), margin: 8, tint: .rose))
        return parts
    }

    private func joint(_ p: CGPoint, _ length: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: p.x + length * sin(angle), y: p.y + length * cos(angle))
    }

    /// Twelve points around a capsule from `a` to `b`: six on each rounded end.
    private func capsule(_ a: CGPoint, _ b: CGPoint, _ r: CGFloat) -> [CGPoint] {
        let angle = atan2(b.y - a.y, b.x - a.x)
        var out: [CGPoint] = []
        for (end, start) in [(b, angle - .pi / 2), (a, angle + .pi / 2)] {
            for i in 0..<6 {
                let t = start + .pi * CGFloat(i) / 5
                out.append(CGPoint(x: end.x + r * cos(t), y: end.y + r * sin(t)))
            }
        }
        return out
    }
}
