import Foundation
import Observation
import SwiftUI

/// The studies screen's state. The clock is `base` plus the time since `clockStart`, so the timeline
/// reads the time at each frame and nothing is written while a scene animates.
@Observable
@MainActor
final class WrapAroundViewModel {
    struct State {
        /// A disc drag in progress: which disc, and where it was when the drag began.
        struct Grab {
            let index: Int
            let origin: CGPoint
        }

        var scene: WrapScene = .drag
        var dark = false
        var largeType = false
        var running = true
        var orbs: [WrapOrb] = WrapOrb.initial
        var base: Double = 0
        var clockStart: Date? = Date()
        var grab: Grab?
    }

    enum Action {
        case selectScene(WrapScene)
        case toggleDarkPaper
        case toggleLargeType
        case togglePause
        case moveDisc(index: Int, translation: CGSize, scale: CGFloat, logicalHeight: CGFloat)
        case endDrag
    }

    private(set) var state: State
    private let repository: any WrapCopyRepository

    init(initialState: State = .init(), repository: any WrapCopyRepository = FixtureWrapCopy()) {
        self.state = initialState
        self.repository = repository
    }

    func text(_ study: WrapStudyText) -> WrapText {
        repository.text(study)
    }

    /// Milliseconds of scene time at `date`. Pausing freezes it; a scene change resets it to zero.
    func elapsed(at date: Date) -> Double {
        guard let clockStart = state.clockStart else { return state.base }
        return state.base + max(0, date.timeIntervalSince(clockStart)) * 1000
    }

    func send(_ action: Action) {
        switch action {
        case .selectScene(let scene):
            state.scene = scene
            state.base = 0
            state.clockStart = state.running ? Date() : nil
        case .toggleDarkPaper:
            state.dark.toggle()
        case .toggleLargeType:
            state.largeType.toggle()
        case .togglePause:
            if state.running {
                state.base = elapsed(at: Date())
                state.clockStart = nil
            } else {
                state.clockStart = Date()
            }
            state.running.toggle()
        case let .moveDisc(index, translation, scale, logicalHeight):
            moveDisc(index, translation: translation, scale: scale, logicalHeight: logicalHeight)
        case .endDrag:
            state.grab = nil
        }
    }

    /// Moves one disc by a drag from where it was when the drag began, kept inside the page.
    private func moveDisc(_ index: Int, translation: CGSize, scale: CGFloat, logicalHeight: CGFloat) {
        guard state.orbs.indices.contains(index) else { return }
        if state.grab?.index != index {
            let orb = state.orbs[index]
            state.grab = State.Grab(index: index, origin: CGPoint(x: orb.x, y: orb.y))
        }
        guard let origin = state.grab?.origin else { return }
        let diameter = state.orbs[index].diameter
        let x = origin.x + translation.width / scale
        let y = origin.y + translation.height / scale
        state.orbs[index].x = min(max(0, x), WrapSpace.logicalWidth - diameter)
        state.orbs[index].y = min(max(0, y), logicalHeight - diameter)
    }
}
