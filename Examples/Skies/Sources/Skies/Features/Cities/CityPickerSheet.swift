import SwiftUI

// The city sheet: the cities in a list, filtered by the search field.
struct CityPickerSheet: View {
    let selectedID: String
    let onSelect: (CityVO) -> Void

    @State private var viewModel = CityPickerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.state.results) { city in
                Button {
                    onSelect(city)
                    dismiss()
                } label: {
                    CityRow(city: city, selected: city.id == selectedID)
                }
                .accessibilityIdentifier("city-\(city.id)")
            }
            .navigationTitle(Strings.Cities.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: queryBinding, prompt: Strings.Cities.searchPrompt)
            .overlay {
                if viewModel.state.results.isEmpty {
                    ContentUnavailableView.search(text: viewModel.state.query)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Cities.done) { dismiss() }
                }
            }
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { viewModel.state.query },
            set: { viewModel.send(.setQuery($0)) })
    }
}
