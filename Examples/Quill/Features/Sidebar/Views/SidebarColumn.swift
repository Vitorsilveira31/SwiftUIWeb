import SwiftUIWeb

/// The right column of a wide window: the trends and the people to follow, or the state while they load or fail.
struct SidebarColumn: View {
  let viewModel: SidebarViewModel

  var body: some View {
    ScrollView {
      if viewModel.state == .loaded {
        VStack(alignment: .leading, spacing: 16) {
          TrendsCard(trends: viewModel.trends)
          WhoToFollowCard(viewModel: viewModel)
        }
        .padding(16)
      } else {
        QuillStatusView(state: viewModel.state, loading: SidebarStrings.loading, failedTitle: SidebarStrings.failedTitle, retry: SidebarStrings.retry) {
          Task { await viewModel.load() }
        }
      }
    }
    .frame(maxHeight: .infinity, alignment: .topLeading)
  }
}
