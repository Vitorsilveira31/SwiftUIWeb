import SwiftUIWeb

/// The stay's content once it is loaded, with the booking panel beside it on wide screens and below it on a phone.
struct DetailBody: View {
  let viewModel: DetailViewModel
  let wide: Bool

  var body: some View {
    if let detail = viewModel.detail, viewModel.state == .loaded {
      if wide {
        HStack(alignment: .top, spacing: 32) {
          DetailInfo(viewModel: viewModel, detail: detail).frame(maxWidth: .infinity)
          BookingPanel(viewModel: viewModel).frame(width: 320)
        }
      } else {
        VStack(alignment: .leading, spacing: 24) {
          DetailInfo(viewModel: viewModel, detail: detail)
          BookingPanel(viewModel: viewModel)
        }
      }
    } else {
      StaylyStatusView(state: viewModel.state, loading: DetailStrings.loading, failedTitle: DetailStrings.failedTitle, retry: DetailStrings.retry) {
        Task { await viewModel.load() }
      }
    }
  }
}
