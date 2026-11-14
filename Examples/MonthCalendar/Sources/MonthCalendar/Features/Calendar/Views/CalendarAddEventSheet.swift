import SwiftUI

// The add-event sheet. Its draft fields are UI-local state; saving sends one action. It starts on the selected day
// at 09:00 for one hour.
struct CalendarAddEventSheet: View {
    let viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var isAllDay = false
    @State private var start: Date
    @State private var end: Date
    @State private var color = EventColor.blue

    init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
        let selectedDay = viewModel.state.selectedDay
        let nine = viewModel.dates.date(atHour: 9, on: selectedDay) ?? selectedDay
        _start = State(initialValue: nine)
        _end = State(initialValue: nine.addingTimeInterval(60 * 60))
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var components: DatePicker.Components {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(Strings.NewEvent.titleField, text: $title)
                        .accessibilityIdentifier("event-title-field")
                }
                Section {
                    Toggle(Strings.NewEvent.allDay, isOn: $isAllDay)
                    DatePicker(Strings.NewEvent.starts, selection: $start, displayedComponents: components)
                    DatePicker(Strings.NewEvent.ends, selection: $end, in: start..., displayedComponents: components)
                }
                Section {
                    Picker(Strings.NewEvent.color, selection: $color) {
                        ForEach(EventColor.allCases, id: \.self) { option in
                            Label(option.title, systemImage: "circle.fill")
                                .foregroundStyle(option.color)
                                .tag(option)
                        }
                    }
                }
            }
            .navigationTitle(Strings.NewEvent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.NewEvent.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.NewEvent.add) { save() }
                        .disabled(trimmedTitle.isEmpty)
                        .accessibilityIdentifier("event-save")
                }
            }
            // Keep the end after the start when the start moves past it.
            .onChange(of: start) { _, newStart in
                if end < newStart {
                    end = newStart.addingTimeInterval(60 * 60)
                }
            }
        }
    }

    private func save() {
        viewModel.send(
            .addEvent(
                NewEvent(title: title, start: start, end: end, isAllDay: isAllDay, color: color)
            )
        )
        dismiss()
    }
}
