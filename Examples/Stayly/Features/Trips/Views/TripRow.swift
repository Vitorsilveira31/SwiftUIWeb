import SwiftUIWeb

/// One reservation: the stay, the dates, the guests and the total.
struct TripRow: View {
  let reservation: StayReservation

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(TripsStrings.reserved).font(.caption).fontWeight(.semibold).foregroundStyle(StaylyPalette.teal)
      Text(reservation.stay.title).font(.headline)
      Text(reservation.stay.city).foregroundStyle(.secondary)
      Text(TripsStrings.dates(StayFormat.day(reservation.checkIn), StayFormat.day(reservation.checkOut)))
      Text(StayCopy.guests(reservation.guests)).foregroundStyle(.secondary)
      if let total = reservation.total {
        Text(StayCopy.totalFor(total, nights: reservation.nights)).fontWeight(.semibold)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: StaylyLayout.cardRadius))
    .overlay { RoundedRectangle(cornerRadius: StaylyLayout.cardRadius).stroke(Color.gray, lineWidth: 1) }
  }
}
