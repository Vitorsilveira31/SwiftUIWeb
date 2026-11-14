# MonthCalendar

A month and agenda calendar: a six-week grid with a swipeable month, a 60-day agenda, and an add-event sheet. It presses on
`LazyVGrid`, `DragGesture` with `.push` transitions, `ScrollViewReader`, `List` with `swipeActions`, `ContentUnavailableView`,
`Form` with `DatePicker` in a `.sheet`, and `Calendar`/`Date.FormatStyle` for all date arithmetic.

```
Sources/MonthCalendar/
  App/            MonthCalendarRootView (NavigationStack, title)
  Core/           Strings
  Data/           CalendarEvent, NewEvent, EventColor, EventRepository, InMemoryEventRepository, SampleEvents, SeedRandom
  Features/Calendar/
    CalendarViewModel, CalendarDates, CalendarGridDay, CalendarMode
    Views/        CalendarView, CalendarMonthView, CalendarMonthHeader, CalendarWeekdayRow, CalendarMonthGrid,
                  CalendarDayCell, CalendarDayEventsList, CalendarAgendaView, CalendarEventRow, CalendarAddEventSheet
```

Run on iOS: open `Darwin/MonthCalendar.xcodeproj`, scheme "MonthCalendar App".
Run in the browser: `make example-web EXAMPLE=MonthCalendar` from the repository root.
