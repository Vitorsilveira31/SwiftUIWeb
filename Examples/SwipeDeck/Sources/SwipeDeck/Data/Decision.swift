import SwiftUI

/// A decision on the top card. The raw value is only a stable order.
enum Decision: Int, Sendable {
    case nope = 1
    case like = 2
    case superLike = 3

    var isLike: Bool { self != .nope }

    /// Decides a released drag. Up past the threshold, and more up than sideways, is a super like; right is a like;
    /// left is a nope; anything else springs back (nil). SwiftUI gives no velocity, so a flick is the distance the
    /// predicted end lies beyond the drag.
    static func verdict(x: CGFloat, y: CGFloat, flickX: CGFloat, flickY: CGFloat, throwAt: CGFloat) -> Decision? {
        let flick: CGFloat = 150
        let up = -y
        if up > abs(x) && (up > throwAt || flickY < -flick) { return .superLike }
        if x > throwAt || flickX > flick { return .like }
        if x < -throwAt || flickX < -flick { return .nope }
        return nil
    }
}
