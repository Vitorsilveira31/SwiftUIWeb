import SwiftUIWeb

/// "1-20 of 100", and the buttons to the older and the newer page.
struct MailboxPager: View {
  let mailbox: MailboxViewModel

  var body: some View {
    HStack(spacing: 6) {
      Text(mailbox.rangeLabel).font(.caption).foregroundStyle(.secondary)
      Button(MailboxStrings.newer) { mailbox.showNewer() }
        .buttonStyle(.plain)
        .disabled(!mailbox.hasNewer)
      Button(MailboxStrings.older) { mailbox.showOlder() }
        .buttonStyle(.plain)
        .disabled(!mailbox.hasOlder)
    }
  }
}
