import SwiftUIWeb

/// A count with what it counts.
struct ProfileStat: View {
  let count: Int
  let label: String

  var body: some View {
    VStack(spacing: 0) {
      Text(Numbers.compact(count)).fontWeight(.semibold)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
  }
}
