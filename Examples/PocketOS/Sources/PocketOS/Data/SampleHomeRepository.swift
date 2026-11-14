// Sample home screen content. The forecast is static: a real app would fetch it.
struct SampleHomeRepository: HomeRepository {
    func tiles() -> [Tile] {
        [
            Tile(id: "messages", title: "Messages", symbol: "message.fill", target: .app(.messages)),
            Tile(id: "reader", title: "Reader", symbol: "book.fill", target: .app(.reader)),
            Tile(id: "camera", title: "Camera", symbol: "camera.fill", target: nil),
            Tile(id: "photos", title: "Photos", symbol: "photo.on.rectangle", target: nil),
            Tile(id: "notes", title: "Notes", symbol: "note.text", target: nil),
            Tile(id: "maps", title: "Maps", symbol: "map.fill", target: nil),
            Tile(id: "music", title: "Music", symbol: "music.note", target: nil),
            Tile(id: "clock", title: "Clock", symbol: "clock.fill", target: nil),
            Tile(id: "calendar", title: "Calendar", symbol: "calendar", target: nil),
            Tile(id: "calculator", title: "Calculator", symbol: "plus.forwardslash.minus", target: nil),
            Tile(id: "weather", title: "Weather", symbol: "cloud.sun.fill", target: nil),
            Tile(id: "settings", title: "Settings", symbol: "gearshape.fill", target: .app(.settings)),
        ]
    }

    func dock() -> [Tile] {
        [
            Tile(id: "messages", title: "Messages", symbol: "message.fill", target: .app(.messages)),
            Tile(id: "reader", title: "Reader", symbol: "book.fill", target: .app(.reader)),
            Tile(id: "pocket", title: "Pocket", symbol: "sparkles", target: .thread(ChatThread.assistantID)),
            Tile(id: "settings", title: "Settings", symbol: "gearshape.fill", target: .app(.settings)),
        ]
    }

    func event() -> CalendarEvent {
        CalendarEvent(title: "Studio review", time: "2:00–3:00 PM · Studio")
    }

    func forecast() -> Forecast {
        Forecast(
            place: "Lisbon", temperature: 21, condition: "Mostly clear", high: 24, low: 15,
            hours: [
                Forecast.Hour(id: "10", label: "10 AM", temperature: 19, symbol: "cloud.sun.fill"),
                Forecast.Hour(id: "12", label: "12 PM", temperature: 21, symbol: "sun.max.fill"),
                Forecast.Hour(id: "14", label: "2 PM", temperature: 23, symbol: "sun.max.fill"),
                Forecast.Hour(id: "16", label: "4 PM", temperature: 24, symbol: "sun.max.fill"),
                Forecast.Hour(id: "18", label: "6 PM", temperature: 22, symbol: "cloud.sun.fill"),
                Forecast.Hour(id: "20", label: "8 PM", temperature: 18, symbol: "moon.stars.fill"),
            ]
        )
    }
}
