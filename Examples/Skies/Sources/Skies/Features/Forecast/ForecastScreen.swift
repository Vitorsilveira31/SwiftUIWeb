import SwiftUI

// The Skies screen: current conditions over an animated sky, the next 24 hours,
// a week of temperatures and the day's details.
struct ForecastScreen: View {
    @State private var viewModel = ForecastViewModel()
    @State private var skyPaused = false
    @State private var showingCities = false
    @AppStorage("skies.units") private var storedUnit: TemperatureUnit = .fahrenheit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = viewModel.state
        let forecast = state.forecast
        let reading = forecast.hour(state.selection)
        let isNow = reading.id == "now"
        let loading = state.loadState == .loading

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                UnitPicker(unit: state.units) { viewModel.send(.setUnits($0)) }

                ForecastHero(
                    city: state.city,
                    reading: reading,
                    day: forecast.day(for: reading),
                    isNow: isNow,
                    loading: loading,
                    unit: state.units,
                    paused: skyPaused || reduceMotion,
                    onTogglePause: { skyPaused.toggle() },
                    onBackToNow: { viewModel.send(.selectHour("now")) })

                if let message = state.loadState.failureMessage {
                    ForecastNotice(message: message) { viewModel.send(.refresh) }
                }

                HourStrip(hours: forecast.hours, selection: state.selection, unit: state.units) {
                    viewModel.send(.selectHour($0))
                }

                LookAhead(days: forecast.days, unit: state.units)

                ElementsSection(
                    reading: reading,
                    day: forecast.day(for: reading),
                    unit: state.units,
                    label: isNow
                        ? Strings.Forecast.rightNow
                        : Strings.Forecast.hourForecast(WallTime.clock(reading.time)))

                ForecastFooter(source: forecast.source, updated: forecast.updated, loading: loading)
            }
            .padding(20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await viewModel.send(.refresh)?.value }
        .task { await viewModel.send(.appear)?.value }
        .onAppear { viewModel.send(.setUnits(storedUnit)) }
        .onChange(of: viewModel.state.units) { _, units in
            storedUnit = units
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { viewModel.send(.useCurrentLocation) } label: {
                    Label(Strings.Forecast.useMyLocation, systemImage: "location.fill")
                }
                .accessibilityIdentifier("use-location")

                Button { showingCities = true } label: {
                    Label(Strings.Cities.title, systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("change-city")
            }
        }
        .sheet(isPresented: $showingCities) {
            CityPickerSheet(selectedID: viewModel.state.city.id) { city in
                viewModel.send(.selectCity(city))
            }
            .presentationDetents([.medium, .large])
        }
    }
}
