import SwiftUIWeb

/// The home page: the mark, the wordmark, the search box, "I am feeling lucky" and the recent searches.
struct SeekrHomeView: View {
  let shell: SeekrShellViewModel
  let home: SeekrHomeViewModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        SeekrMark(size: 72)
        SeekrWordmark(size: 64)
        Text(HomeStrings.tagline).foregroundStyle(.secondary)
        SeekrSearchBox(shell: shell)
        Button(HomeStrings.lucky) {
          Task {
            if let link = await home.luckyLink(for: shell.query), let url = URL(string: link) { openURL(url) }
          }
        }
        .buttonStyle(.bordered)
        if let notice = home.notice {
          Text(notice).font(.caption).foregroundStyle(.secondary)
        }
        SeekrRecentSearches(shell: shell)
      }
      .padding(.top, 72)
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
      .frame(maxWidth: SeekrLayout.homeWidth)
      .frame(maxWidth: .infinity)
    }
  }
}
