import SwiftUIWeb

/// The topics people are talking about, with how many posts each has.
struct TrendsCard: View {
  let trends: [QuillTrend]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(SidebarStrings.trends).font(.title3).fontWeight(.bold).padding(12)
      ForEach(trends) { trend in
        VStack(alignment: .leading, spacing: 2) {
          Text(SidebarStrings.trending).font(.caption).foregroundStyle(.secondary)
          Text(trend.topic).fontWeight(.semibold)
          Text(SidebarStrings.posts(trend.posts)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
    }
    .background(Color.secondary.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}
