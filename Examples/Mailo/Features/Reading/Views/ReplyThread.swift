import SwiftUIWeb

/// The message's replies, the comments of its post, in the order the service keeps them.
struct ReplyThread: View {
  let reading: ReadingViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(ReadingStrings.repliesTitle).font(.headline)
      switch reading.state {
      case .loading, .failed:
        MailoStatusView(state: reading.state, loading: ReadingStrings.loading, failedTitle: ReadingStrings.failedTitle, retry: ReadingStrings.retry) {
          Task { await reading.loadReplies() }
        }
      case .loaded:
        if reading.replies.isEmpty {
          Text(ReadingStrings.noReplies).foregroundStyle(.secondary)
        }
        ForEach(reading.replies) { reply in
          ReplyRow(reply: reply)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
