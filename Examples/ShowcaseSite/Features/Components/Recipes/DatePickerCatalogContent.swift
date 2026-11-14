import SwiftUIWeb

/// The `DatePicker` itself, before a style is applied to it; it shows the date and time fields the knob picks.
struct DatePickerCatalogContent: View {
  let components: DatePickerComponents
  @Binding var date: Date

  var body: some View {
    DatePicker("Date", selection: $date, displayedComponents: components)
  }
}
