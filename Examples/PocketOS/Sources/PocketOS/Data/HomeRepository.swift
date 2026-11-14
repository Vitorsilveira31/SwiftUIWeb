// What the home screen shows: the app tiles, the dock, today's event and the forecast.
protocol HomeRepository: Sendable {
    func tiles() -> [Tile]
    func dock() -> [Tile]
    func event() -> CalendarEvent
    func forecast() -> Forecast
}
