import SwiftUIWeb

/// Quill: on a wide window the rail, the timeline and the trends side by side; on a phone (or a narrow window) the timeline with a bottom bar.
/// The view models live here, so both layouts show the same state; only one of the two is shown at a time.
struct QuillRootView: View {
  @State private var timeline: TimelineViewModel
  @State private var sidebar: SidebarViewModel
  @State private var composer: ComposerViewModel

  init(dependencies: QuillDependencies) {
    _timeline = State(wrappedValue: TimelineViewModel(loadTimeline: dependencies.loadTimeline, loadReplies: dependencies.loadReplies, addReply: dependencies.addReply))
    _sidebar = State(wrappedValue: SidebarViewModel(loadWhoToFollow: dependencies.loadWhoToFollow, loadTrends: dependencies.loadTrends))
    _composer = State(wrappedValue: ComposerViewModel(publish: dependencies.publishPost))
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 0) {
        QuillRail(onCompose: { timeline.composing = true })
          .frame(width: QuillLayout.railWidth, alignment: .topLeading)
        TimelineColumn(timeline: timeline, composer: composer, showsComposer: true)
          .frame(minWidth: QuillLayout.feedMinWidth, maxWidth: .infinity)
        SidebarColumn(viewModel: sidebar)
          .frame(width: QuillLayout.sidebarWidth, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      VStack(spacing: 0) {
        TimelineColumn(timeline: timeline, composer: composer, showsComposer: false)
        QuillBottomBar(onCompose: { timeline.composing = true })
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .sheet(item: Binding(get: { timeline.opened }, set: { _ in timeline.finishThread() }), onDismiss: { timeline.finishThread() }) { post in
      PostDetailView(viewModel: timeline.thread ?? timeline.threadModel(for: post)) { timeline.finishThread() }
    }
    .sheet(isPresented: Binding(get: { timeline.composing }, set: { timeline.composing = $0 })) {
      ComposerSheet(viewModel: composer, posted: { post in
        timeline.prepend(post)
        timeline.composing = false
      }, close: { timeline.composing = false })
    }
    .task { await timeline.load() }
    .task { await sidebar.load() }
  }
}
