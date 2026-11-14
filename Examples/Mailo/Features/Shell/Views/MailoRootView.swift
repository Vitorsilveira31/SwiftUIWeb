import SwiftUIWeb

/// Mailo: the brand and the search on top, then the mailbox and the reading pane in the layout the width asks for.
struct MailoRootView: View {
  @State private var app: MailoController

  init(dependencies: MailoDependencies) {
    _app = State(wrappedValue: MailoController(dependencies: dependencies))
  }

  var body: some View {
    VStack(spacing: 0) {
      MailoTopBar(mailbox: app.mailbox)
      Divider()
      GeometryReader { proxy in
        MailoWorkspace(app: app, wide: proxy.size.width >= MailoLayout.wideWidth)
      }
    }
    .background(MailoPalette.paper)
    .preferredColorScheme(.light)
    .task { await app.start() }
    .sheet(isPresented: Binding(get: { app.compose != nil }, set: { if !$0 && app.compose != nil { app.closeCompose() } })) {
      if let compose = app.compose {
        ComposeSheet(viewModel: compose, close: { app.closeCompose() })
      }
    }
  }
}
