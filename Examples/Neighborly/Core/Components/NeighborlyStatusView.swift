import SwiftUIWeb

/// What a screen shows instead of its content while it loads or when it could not: a spinner or the reason with a way to try again.
struct NeighborlyStatusView: View {
  let state: LoadState
  let loading: String
  let failedTitle: String
  let retry: String
  var padding: CGFloat = 48
  let action: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(spacing: 12) {
      switch state {
      case .loading:
        ProgressView()
        Text(loading).foregroundStyle(.secondary)
      case .failed(let reason):
        Text(failedTitle).font(.headline)
        Text(reason).font(.caption).foregroundStyle(.secondary)
        Button(retry, action: action).buttonStyle(.bordered)
      case .loaded:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, padding)
  }
}
