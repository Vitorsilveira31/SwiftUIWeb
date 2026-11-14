import Observation
import SwiftUI

/// The deck's state and the decisions made on it. Every change that moves a card goes through `withAnimation`.
/// The live drag of the top card is not here: the card moves itself and reports only the decision on release.
@Observable
@MainActor
final class SwipeDeckViewModel {
    struct State: Equatable {
        /// The top card's place in the deck; `profiles.count` once the deck is exhausted.
        var index = 0
        /// The photo showing on the top card, and on the card thrown last.
        var photo = 0
        var flungPhoto = 0
        /// Height the last thrown card was released at; it leaves from there.
        var flungY: CGFloat = 0
        /// Every decision so far; undo pops the last one.
        var history: [Decision] = []
        /// The person who likes the user back, when a like just matched.
        var matchedIndex: Int?
    }

    enum Action {
        /// Throws the top card. `releasedY` is the height a dragged card was let go at; the buttons pass 0.
        case throwCard(Decision, releasedY: CGFloat)
        case undo
        case startOver
        case dismissMatch
        case changePhoto(by: Int)
    }

    private(set) var state: State
    let profiles: [Profile]

    init(initialState: State = .init(), repository: some ProfileRepository) {
        state = initialState
        profiles = repository.profiles()
    }

    var isExhausted: Bool { state.index >= profiles.count }
    var likes: Int { state.history.filter { $0.isLike }.count }
    var lastDecision: Decision? { state.history.last }

    /// The cards that can show: the one thrown last (parked where it left), the top, and the two under it.
    /// Bottom first, so each paints over the one before it and the top card is last among the visible ones.
    var visibleProfiles: [Profile] {
        let low = max(0, state.index - 1)
        let high = min(profiles.count - 1, state.index + 2)
        guard low <= high else { return [] }
        return Array(profiles[low...high].reversed())
    }

    func photo(for n: Int) -> Int {
        if n == state.index { return state.photo }
        return n == state.index - 1 ? state.flungPhoto : 0
    }

    func send(_ action: Action) {
        switch action {
        case let .throwCard(decision, releasedY):
            throwCard(decision, releasedY: releasedY)
        case .undo:
            undo()
        case .startOver:
            startOver()
        case .dismissMatch:
            withAnimation(.easeOut(duration: 0.25)) {
                state.matchedIndex = nil
            }
        case let .changePhoto(step):
            // Clamped to the first and the last photo.
            state.photo = min(max(state.photo + step, 0), Profile.photoCount - 1)
        }
    }

    private func throwCard(_ decision: Decision, releasedY: CGFloat) {
        guard !isExhausted else { return }
        let matches = decision.isLike && profiles[state.index].likesYou
        withAnimation(DeckMotion.spring) {
            state.history.append(decision)
            state.flungY = releasedY
            state.flungPhoto = state.photo
            state.photo = 0
            state.matchedIndex = matches ? state.index : nil
            state.index += 1
        }
    }

    /// Takes the last decision back: its card returns from where it was thrown.
    private func undo() {
        guard !state.history.isEmpty else { return }
        withAnimation(DeckMotion.spring) {
            state.history.removeLast()
            state.index -= 1
            state.matchedIndex = nil
            state.photo = 0
        }
    }

    private func startOver() {
        withAnimation(DeckMotion.spring) {
            state.history = []
            state.index = 0
            state.matchedIndex = nil
            state.photo = 0
            state.flungPhoto = 0
        }
    }
}
