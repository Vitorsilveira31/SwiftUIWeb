import SwiftUI

/// A draggable disc of study 01. The drag moves it by the gesture's translation, kept inside the page.
struct WrapOrbHandle: View {
    let viewModel: WrapAroundViewModel
    let index: Int
    let metrics: WrapMetrics

    var body: some View {
        let orb = viewModel.state.orbs[index]
        let side = orb.diameter * metrics.scale
        Circle()
            .fill(orb.tint.color)
            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .frame(width: side, height: side)
            .contentShape(Circle())
            .position(
                x: (orb.x + orb.diameter / 2) * metrics.scale,
                y: (orb.y + orb.diameter / 2) * metrics.scale
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.send(.moveDisc(
                            index: index,
                            translation: value.translation,
                            scale: metrics.scale,
                            logicalHeight: metrics.logicalHeight
                        ))
                    }
                    .onEnded { _ in
                        viewModel.send(.endDrag)
                    }
            )
            .accessibilityIdentifier("orb-\(index + 1)")
    }
}
