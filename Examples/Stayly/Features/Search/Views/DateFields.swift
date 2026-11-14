import SwiftUIWeb

/// The check-in and check-out days, and how many nights they make.
struct DateFields: View {
  let viewModel: SearchViewModel

  /// Today to two years ahead: a check-out far in the future would overflow the total.
  private var bookable: ClosedRange<Date> {
    let today = StayDays.number(Date())
    return StayDays.date(day: today) ... StayDays.date(day: today + 730)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 16) {
        DatePicker(SearchStrings.checkIn, selection: Binding(get: { viewModel.checkIn }, set: { viewModel.setCheckIn($0) }), in: bookable, displayedComponents: .date)
        DatePicker(SearchStrings.checkOut, selection: Binding(get: { viewModel.checkOut }, set: { viewModel.setCheckOut($0) }), in: bookable, displayedComponents: .date)
      }
      Text(StayCopy.nights(viewModel.nights)).font(.caption).foregroundStyle(.secondary)
    }
  }
}
