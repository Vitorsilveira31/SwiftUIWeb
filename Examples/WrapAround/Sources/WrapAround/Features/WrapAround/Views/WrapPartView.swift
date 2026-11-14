import SwiftUI

/// Draws one exclusion shape, or its caption, using layout positions only.
struct WrapPartView: View {
    let part: WrapExclusion

    var body: some View {
        switch part.outline {
        case .circle(let center, let radius):
            if let tint = part.tint {
                Circle()
                    .fill(tint.color)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                    .accessibilityIdentifier(part.id)
            }
        case .polygon(let points):
            if let tint = part.tint {
                WrapPolygon(points: points)
                    .fill(tint.color)
                    .contentShape(WrapPolygon(points: points))
                    .accessibilityIdentifier(part.id)
            }
        case .rect(let rect):
            if let caption = part.caption {
                WrapCaptionView(caption: caption, rect: rect)
                    .accessibilityIdentifier(part.id)
            }
        }
    }
}
