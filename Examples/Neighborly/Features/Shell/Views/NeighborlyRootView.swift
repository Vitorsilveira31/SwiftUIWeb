import SwiftUIWeb

/// Neighborly: the brand on top; three columns when the window is wide enough for them, and one column with a bottom bar when it is not (a phone).
struct NeighborlyRootView: View {
  @State private var shell: ShellViewModel

  init(dependencies: NeighborlyDependencies) {
    _shell = State(wrappedValue: ShellViewModel(dependencies: dependencies))
  }

  var body: some View {
    VStack(spacing: 0) {
      NeighborlyTopBar(shell: shell)
      Divider()
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 0) {
          ShortcutsColumn(shell: shell)
            .frame(width: NeighborlyLayout.sideWidth, alignment: .topLeading)
          NeighborlyContent(shell: shell)
          ContactsColumn(viewModel: shell.contacts) { id in shell.openPerson(id) }
            .frame(width: NeighborlyLayout.sideWidth, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        VStack(spacing: 0) {
          NeighborlyContent(shell: shell)
          NeighborlyBottomBar(shell: shell)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(NeighborlyPalette.canvas)
    .task { await shell.start() }
  }
}
