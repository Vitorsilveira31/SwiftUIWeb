import SwiftUIWeb

/// The feed: the tabs, the composer (on a wide window), the posts a page at a time, and the state while they load or fail.
struct TimelineColumn: View {
  let timeline: TimelineViewModel
  let composer: ComposerViewModel
  let showsComposer: Bool

  var body: some View {
    VStack(spacing: 0) {
      TimelineTabs(viewModel: timeline)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if showsComposer {
            ComposerView(viewModel: composer) { post in timeline.prepend(post) }
            Divider()
          }
          if timeline.state == .loaded {
            ForEach(timeline.posts, id: \.self) { post in
              PostCard(viewModel: timeline, post: post)
            }
            TimelineFooter(viewModel: timeline)
          } else {
            QuillStatusView(state: timeline.state, loading: TimelineStrings.loading, failedTitle: TimelineStrings.failedTitle, retry: TimelineStrings.retry) {
              Task { await timeline.load() }
            }
          }
        }
        .frame(maxWidth: QuillLayout.feedMaxWidth)
        .frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
