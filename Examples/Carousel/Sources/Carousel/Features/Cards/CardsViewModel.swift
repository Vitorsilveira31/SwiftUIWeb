import Observation

/// State for the Cards screen. Scroll positions are card and post ids: the
/// views bind them to `scrollPosition(id:)` through `stripScrolled` and
/// `feedScrolled`, so a position survives switching between strip and feed.
@MainActor
@Observable
final class CardsViewModel {
    struct State {
        enum Page: Sendable { case strip, feed }

        var page: Page = .strip
        var eager = false
        var stripPosition: String?
        var feedPosition: String?
        var cards: [CardVO] = []
        var eagerCards: [CardVO] = []
        var posts: [PostVO] = []
    }

    enum Action {
        case far
        case toggleEager
        case togglePage
        case feedDown
        case feedTop
        case stripScrolled(String?)
        case feedScrolled(String?)
    }

    private(set) var state: State
    private var farTarget = 0

    /// About 100,000 points at the average card pitch (about 147 points).
    private static let farStep = 680
    /// Feed post near 6,000 points from the top at the average row height.
    private static let feedDownIndex = 44
    private static let cardCount = 25_000
    /// The eager strip lays out only this many cards.
    private static let eagerCount = 2_000
    private static let postCount = 200

    init(initialState: State = .init(), repository: any CardsRepository = SampleCardsRepository()) {
        state = initialState
        let cards = repository.cards(count: Self.cardCount)
        state.cards = cards
        state.eagerCards = Array(cards.prefix(Self.eagerCount))
        state.posts = repository.posts(count: Self.postCount)
    }

    func send(_ action: Action) {
        switch action {
        case .far:
            far()
        case .toggleEager:
            state.eager.toggle()
        case .togglePage:
            state.page = state.page == .feed ? .strip : .feed
        case .feedDown:
            state.feedPosition = state.posts[Self.feedDownIndex].id
        case .feedTop:
            state.feedPosition = state.posts.first?.id
        case .stripScrolled(let id):
            state.stripPosition = id
        case .feedScrolled(let id):
            state.feedPosition = id
        }
    }

    /// Advances a cumulative target, so repeated presses keep moving, and
    /// clamps at the last card.
    private func far() {
        guard let last = state.cards.indices.last else { return }
        farTarget = min(farTarget + Self.farStep, last)
        state.stripPosition = state.cards[farTarget].id
    }
}
