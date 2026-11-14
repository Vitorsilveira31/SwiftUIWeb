import SwiftUIWeb

/// The booking: the price per night, the dates and guests, the total, and the button that reserves the stay.
struct BookingPanel: View {
  let viewModel: DetailViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(StayCopy.perNight(viewModel.stay.pricePerNight)).font(.title3).fontWeight(.bold)
      Divider()
      HStack {
        Text(DetailStrings.checkIn)
        Spacer()
        Text(StayFormat.day(viewModel.query.checkIn))
      }
      HStack {
        Text(DetailStrings.checkOut)
        Spacer()
        Text(StayFormat.day(viewModel.query.checkOut))
      }
      HStack {
        Text(DetailStrings.guests)
        Spacer()
        Text(StayCopy.guests(viewModel.query.guests))
      }
      Divider()
      if let total = viewModel.total {
        Text(StayCopy.totalFor(total, nights: viewModel.query.nights)).fontWeight(.semibold)
      }
      if let reservation = viewModel.reservation {
        Text(DetailStrings.confirmedTitle).font(.headline).foregroundStyle(StaylyPalette.teal)
        Text(DetailStrings.confirmedText).foregroundStyle(.secondary)
        if let total = reservation.total {
          Text(StayCopy.totalFor(total, nights: reservation.nights)).font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Button(viewModel.isReserving ? DetailStrings.reserving : DetailStrings.reserve) { Task { await viewModel.reserve() } }
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.isReserving)
          .frame(maxWidth: .infinity)
        if viewModel.reserveFailed {
          Text(DetailStrings.reserveFailed).font(.caption).foregroundStyle(StaylyPalette.coral)
        }
      }
    }
    .padding(20)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: StaylyLayout.cardRadius))
    .overlay { RoundedRectangle(cornerRadius: StaylyLayout.cardRadius).stroke(Color.gray, lineWidth: 1) }
  }
}
