import SwiftUIWeb

/// A stay's page: the way back, the title, then the gallery, the host and the booking panel (beside them on wide screens).
struct DetailView: View {
  let viewModel: DetailViewModel
  let back: @MainActor @Sendable () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Button(DetailStrings.back, action: back).buttonStyle(.bordered)
        StayHeading(stay: viewModel.stay)
        GeometryReader { proxy in
          DetailBody(viewModel: viewModel, wide: proxy.size.width > StaylyLayout.compactWidth)
        }
      }
      .padding(20)
      .frame(maxWidth: StaylyLayout.detailWidth)
      .frame(maxWidth: .infinity)
    }
    .task { if viewModel.detail == nil { await viewModel.load() } }
  }
}
