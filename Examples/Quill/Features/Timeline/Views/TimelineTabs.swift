import SwiftUIWeb

/// The two feeds at the top of the timeline; the one chosen has a teal line under it.
struct TimelineTabs: View {
  let viewModel: TimelineViewModel

  var body: some View {
    HStack(spacing: 0) {
      ForEach(QuillFeed.allCases, id: \.self) { feed in
        Button { Task { await viewModel.select(feed) } } label: {
          Text(TimelineStrings.title(for: feed))
            .fontWeight(viewModel.feed == feed ? .bold : .regular)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
              if viewModel.feed == feed { Rectangle().fill(QuillPalette.teal).frame(height: 3) }
            }
        }
        .buttonStyle(.plain)
      }
    }
  }
}
