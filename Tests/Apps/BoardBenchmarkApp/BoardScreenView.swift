import SwiftUIWeb

/// The board screen: the toolbar, then the list beside the detail.
struct BoardScreenView: View {
  let model: BoardModel

  var body: some View {
    let visible = model.visible
    VStack(alignment: .leading, spacing: 0) {
      BoardToolbarView(model: model, resultCount: visible.count)
      HStack(alignment: .top, spacing: 20) {
        BoardListView(model: model, works: visible).frame(maxWidth: .infinity)
        BoardDetailView(work: model.selected).frame(width: 280, alignment: .topLeading)
      }
    }
  }
}
