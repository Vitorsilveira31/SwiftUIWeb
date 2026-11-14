import SwiftUIWeb

/// A message open: its header, its body, its thread of replies and the box to reply in.
struct ReadingPane: View {
  let app: MailoController
  let reading: ReadingViewModel
  let narrow: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ReadingHeader(app: app, reading: reading, narrow: narrow)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text(reading.message.body)
          Divider()
          ReplyThread(reading: reading)
          ReplyComposer(reading: reading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.white)
  }
}
