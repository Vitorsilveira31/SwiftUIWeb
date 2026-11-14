import SwiftUI

/// The vertical feed. The eager branch is a VStack of every row; the
/// virtualized branch is a LazyVStack, and its rows use lazy inner lists.
struct FeedView: View {
    let viewModel: CardsViewModel

    private var feedPosition: Binding<String?> {
        Binding(
            get: { viewModel.state.feedPosition },
            set: { viewModel.send(.feedScrolled($0)) }
        )
    }

    var body: some View {
        if viewModel.state.eager {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(viewModel.state.posts) { post in
                        FeedPostView(post: post, virtual: false)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: feedPosition)
            .accessibilityIdentifier("feed")
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.state.posts) { post in
                        FeedPostView(post: post, virtual: true)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: feedPosition)
            .accessibilityIdentifier("feed")
        }
    }
}
