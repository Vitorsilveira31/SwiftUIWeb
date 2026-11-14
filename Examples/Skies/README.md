# Skies

A weather screen: the current conditions over an animated sky, the next 24 hours, a week of temperatures and the day's details. It loads a live forecast from Open-Meteo and falls back to a built-in sample. It presses on `TimelineView` with `Canvas` for the sky, `@Observable` view models, `ScrollView(.horizontal)` with `LazyHStack`, `LazyVGrid` with `gridCellColumns`, `.searchable`, `.sheet` with `presentationDetents`, `.refreshable`, and `@AppStorage` for the unit.

```
Sources/Skies/
  App/            SkiesRootView (NavigationStack, title)
  Core/           Strings (per feature), WallTime, CardStyle, Links
  Data/
    Responses/    ForecastResponse (Open-Meteo wire type)
    ViewObjects/  CityVO, HourVO, DayVO, ForecastVO, TemperatureUnit, WeatherCondition
    Repositories/ ForecastRepository, OpenMeteo and Sample implementations, CityRepository
  Features/
    Forecast/     ForecastScreen, ForecastViewModel, Views/
    Cities/       CityPickerSheet, CityPickerViewModel, Views/
    Sky/          SkyCanvas and the painters: gradient, stars, sun, clouds, ridges, precipitation
```

Run on iOS: open `Darwin/Skies.xcodeproj` and choose the scheme "Skies App".

Run in the browser: `make example-web EXAMPLE=Skies` from the repository root.
